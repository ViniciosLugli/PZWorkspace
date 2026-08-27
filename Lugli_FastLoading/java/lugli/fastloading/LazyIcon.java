package lugli.fastloading;

import java.lang.reflect.Field;

import me.zed_0xff.zombie_buddy.Patch;

import zombie.core.textures.Texture;
import zombie.debug.DebugLog;
import zombie.scripting.objects.Item;

/**
 * Stops the script parser from eagerly loading every item's inventory icon.
 * -Dfastloading.lazyicon=on (default OFF).
 *
 * Item.DoParam's Icon branch runs once per script item -- 13,040 of them on a 300+ list -- and
 * calls Texture.trygetTexture, which queues a file load for media/textures/Item_X.png. Those are
 * 7,104 of the 11,528 loose-image tasks a launch queues, against roughly 545 distinct textures a
 * session actually binds. Every one of them is also a ~6.4 ms upload on the render thread and a
 * live direct buffer against AssetThrottle's budget, which measures as saturated during a world
 * load.
 *
 * WHAT IS DEFERRED, AND WHAT DELIBERATELY IS NOT
 *   normalTexture only. worldTexture stays eager (getSharedTexture returns null cheaply for the
 *   names that do not exist, which is most of them) and the FOOD variant block is reproduced
 *   EXACTLY, because there trygetTexture's null return is not a load but an existence test: it
 *   selects whether the stored name is Rotten, Spoiled or _Rotten. Changing that would silently
 *   rewrite specialWorldTextureNames.
 *
 * WHY A HELPER AND NOT AN INLINED BODY
 *   The advice is inlined into zombie.scripting.objects.Item and may only touch public members
 *   Item.itemType is private, so the branch cannot be reproduced in the advice itself.
 *   Delegating to this class costs one call and makes reflection legal. DoParam runs at parse
 *   only, so per-call reflection here is affordable -- unlike a per-frame path.
 *
 * FAIL OPEN, ALWAYS. Any reflection or field problem latches the whole part off and lets the
 * engine's own branch run, so the worst case is vanilla behaviour and one log line.
 */
public final class LazyIcon {

    public static final String TAG = "[FastLoading/lazyicon]";

    // public: read from advice bodies inlined into Item and InventoryItem, which then access
    // these as their own. Anything private throws IllegalAccessError at runtime.
    public static final boolean ON =
            "on".equals(System.getProperty("fastloading.lazyicon", "off"));

    /** Latched by any failure. Once set, every hook falls through to the engine. */
    public static volatile boolean off;

    public static volatile long deferred;      // icons whose load was NOT queued at parse
    public static volatile long resolved;      // icons a reader later actually asked for
    private static volatile boolean announced;

    private static Field fItemType;
    private static Field fScriptItem;

    private LazyIcon() {}

    /**
     * Returns true when this call has been handled and the engine's own Icon branch must be
     * skipped. Anything other than the Icon parameter returns false immediately.
     */
    public static boolean handleIcon(Item item, String param, String val) {
        if (!ON || off || item == null || param == null || val == null) {
            return false;
        }
        if (!announced) {
            announced = true;
            DebugLog.log(TAG + " armed: item icons resolve on first use, not at script parse");
        }
        if (!param.trim().equalsIgnoreCase("Icon")) {
            return false;
        }
        try {
            item.icon = val;
            item.itemName = "Item_" + val;

            // NOT loaded. This is the whole point; a reader resolves it via resolve() below.
            item.normalTexture = null;

            item.worldTextureName =
                    item.itemName.replace("Item_", "media/inventory/world/WItem_") + ".png";
            item.worldTexture = Texture.getSharedTexture(item.worldTextureName);

            if (isFood(item)) {
                food(item);
            }
            deferred++;
            return true;
        } catch (Throwable t) {
            off = true;
            DebugLog.log(TAG + " disabled after " + deferred + " icon(s), engine branch restored: " + t);
            return false;
        }
    }

    /**
     * The FOOD block, reproduced call for call from Item.DoParam. It is duplicated rather than
     * deferred on purpose: each trygetTexture here decides which variant NAME is stored, so its
     * null return carries meaning that a placeholder would destroy.
     */
    private static void food(Item item) {
        Texture texRotten = Texture.trygetTexture(item.itemName + "Rotten");
        String wTexRotten = item.worldTextureName.replace(".png", "Rotten.png");
        if (texRotten == null) {
            texRotten = Texture.trygetTexture(item.itemName + "Spoiled");
            wTexRotten = wTexRotten.replace("Rotten.png", "Spoiled.png");
        }
        if (texRotten == null) {
            texRotten = Texture.trygetTexture(item.itemName + "_Rotten");
            wTexRotten = wTexRotten.replace("Rotten.png", "_Rotten.png");
        }

        item.specialWorldTextureNames.add(wTexRotten);
        item.specialTextures.add(texRotten);
        item.specialTextures.add(Texture.trygetTexture(item.itemName + "Cooked"));
        item.specialWorldTextureNames.add(item.worldTextureName.replace(".png", "Cooked.png"));

        Texture texOverdone = Texture.trygetTexture(item.itemName + "Overdone");
        String wTexOverdone = item.worldTextureName.replace(".png", "Overdone.png");
        if (texOverdone == null) {
            texOverdone = Texture.trygetTexture(item.itemName + "Burnt");
            wTexOverdone = wTexOverdone.replace("Overdone.png", "Burnt.png");
        }
        if (texOverdone == null) {
            texOverdone = Texture.trygetTexture(item.itemName + "_Burnt");
            wTexOverdone = wTexOverdone.replace("Overdone.png", "_Burnt.png");
        }

        item.specialTextures.add(texOverdone);
        item.specialWorldTextureNames.add(wTexOverdone);
    }

    /** Item.itemType is private, which is the only reason this class exists as a helper. */
    private static boolean isFood(Item item) throws Exception {
        if (fItemType == null) {
            Field f = Item.class.getDeclaredField("itemType");
            f.setAccessible(true);
            fItemType = f;
        }
        Object v = fItemType.get(item);
        return v != null && "FOOD".equals(v.toString());
    }

    /**
     * Resolve on first read. Called from the getter and from InventoryItem.getTexture(), both of
     * which run long before an icon reaches the screen -- which matters, because Texture.bind()
     * substitutes the red/white error texture for anything not ready (Texture.java:678-688).
     *
     * The Question_On fallback is the engine's own, kept identical so a genuinely missing icon
     * looks exactly as it does in vanilla.
     */
    public static Texture resolve(Item item) {
        if (!ON || off || item == null) {
            return item == null ? null : item.normalTexture;
        }
        // Deliberately does NOT trust a non-null field.
        //
        // Something in the parse pipeline leaves a different texture on two items of 12,768
        // (Base.ClubHammer, Base.Crystal_Large), and four cycles of instruments could not name it:
        // trygetTexture resolves correctly in both arms, resolve() demonstrably returns the right
        // texture, and InitLoadPP -- the only other write site -- runs 14,580 times and never once
        // sees an item whose icon is set, so its IconsForTexture fallback cannot be the writer.
        //
        // Rather than a fifth guess, recompute what vanilla's Icon branch would have produced and
        // make that authoritative. Item.java:1994-1996 is trygetTexture(itemName) with a
        // Question_On fallback, which is exactly what this does, so the answer matches vanilla by
        // construction regardless of what wrote the field.
        String want = expectedName(item);
        if (want == null) {
            return item.normalTexture;
        }
        if (item.normalTexture != null && want.equals(item.normalTexture.getName())) {
            return item.normalTexture;
        }
        // An item with no Icon param never enters the branch this part defers, so itemName is
        // still null and vanilla leaves normalTexture null too. Substituting the question mark
        // here would invent an icon for 634 items that are supposed to have none -- which is
        // exactly what the first build did, and what Dev_IconChecksum caught: nil 634 -> 0 and
        // question 349 -> 983.
        try {
            Texture t = Texture.trygetTexture(want);
            if (t == null) {
                // The engine's own fallback, and only on the path the engine would have taken.
                t = Texture.getSharedTexture("media/inventory/Question_On.png");
            }
            item.normalTexture = t;
            resolved++;
            return t;
        } catch (Throwable e) {
            off = true;
            DebugLog.log(TAG + " resolve failed after " + resolved + " icon(s): " + e);
            return null;
        }
    }

    /** InventoryItem.scriptItem is protected, so the inlined advice cannot read it directly. */
    public static Texture resolveFor(Object inventoryItem) {
        if (!ON || off || inventoryItem == null) {
            return null;
        }
        try {
            if (fScriptItem == null) {
                // protected, and declared on InventoryItem while the instance is often a
                // subclass, so the hierarchy has to be walked.
                Field f = null;
                for (Class<?> c = inventoryItem.getClass(); c != null && f == null; c = c.getSuperclass()) {
                    try {
                        f = c.getDeclaredField("scriptItem");
                    } catch (NoSuchFieldException ignored) {
                        // keep walking
                    }
                }
                if (f == null) {
                    throw new NoSuchFieldException("InventoryItem.scriptItem");
                }
                f.setAccessible(true);
                fScriptItem = f;
            }
            Object si = fScriptItem.get(inventoryItem);
            return si instanceof Item ? resolve((Item)si) : null;
        } catch (Throwable e) {
            off = true;
            DebugLog.log(TAG + " resolveFor failed: " + e);
            return null;
        }
    }

    /**
     * Counted and announced, because "the advice did not attach" and "the branch never applied"
     * are indistinguishable from the outcome, and the first build of this hook was silently the
     * former.
     */
    public static void postParse(Item item) {
        if (!postParseSeen) {
            postParseSeen = true;
            DebugLog.log(TAG + " InitLoadPP hook is live");
        }
        // Unconditional counts. "Hook is live" fires once, for whatever item happened to be
        // first, and says nothing about whether the hook reaches the items under investigation.
        ppCalls++;
        if (item != null && hadIconParam(item)) {
            ppWithIcon++;
            if (item.normalTexture != null) {
                ppWithIconAndTexture++;
            }
        }
        // Keyed on `icon`, NOT on itemName. Script merge produces Item instances that carry the
        // parsed icon but a null itemName, and on those the engine's IconsForTexture fallback
        // (Item.java:1472-1473) wins -- which is how Base.ClubHammer came out as
        // Item_ClubHammer_Forged while resolve() was demonstrably returning Item_ClubHammer for a
        // different instance of the same item.
        if (item != null && hadIconParam(item) && item.normalTexture != null) {
            item.normalTexture = null;
            reDeferred++;
        }
    }


    /**
     * "This item declared an Icon" -- true wherever the branch we defer would have run.
     * Item.icon is public and defaults to "None" (Item.java:75), and unlike itemName it survives
     * whatever copying script merge does.
     */
    /**
     * The texture name vanilla's Icon branch would have used, or null for an item that never
     * declared an Icon -- those keep a null normalTexture in vanilla and must keep one here.
     */
    private static String expectedName(Item item) {
        if (item.itemName != null) {
            return item.itemName;
        }
        return hadIconParam(item) ? "Item_" + item.icon : null;
    }

    private static boolean hadIconParam(Item item) {
        return item.icon != null && !"None".equals(item.icon) && !item.icon.isEmpty();
    }

    public static volatile long reDeferred;
    public static volatile long ppCalls;
    public static volatile long ppWithIcon;
    public static volatile long ppWithIconAndTexture;
    private static volatile boolean postParseSeen;

    public static String status() {
        if (!ON) return "off";
        if (off) return "DEFECT";
        return deferred + " icon(s) deferred, " + resolved + " resolved on demand; InitLoadPP "
             + ppCalls + " call(s), " + ppWithIcon + " with an icon, " + ppWithIconAndTexture
             + " of those already textured, " + reDeferred + " re-deferred";
    }

    /**
     * DoParam is overloaded -- DoParam(String) splits and re-calls DoParam(String, String) -- and
     * ZombieBuddy matches by name, so both are patched. Dispatch on AllArguments rather than a
     * declared signature, the same way BootPatches handles getCanonicalFile's three overloads.
     */
    @Patch(className = "zombie.scripting.objects.Item", methodName = "DoParam")
    public static class Parse {
        @Patch.OnEnter(skipOn = true)
        public static boolean enter(@Patch.This Item item, @Patch.AllArguments Object[] args) {
            if (args == null || args.length != 2) {
                return false;
            }
            return LazyIcon.handleIcon(item, (String)args[0], (String)args[1]);
        }
    }

    /**
     * The engine has its OWN null-texture fallback, and deferral makes it fire where it would not.
     *
     * Item.InitLoadPP ends with (Item.java:1472-1473):
     *     if (normalTexture == null && iconsForTexture != null && !iconsForTexture.isEmpty())
     *         normalTexture = Texture.trygetTexture("Item_" + iconsForTexture.get(0));
     *
     * In vanilla that branch is unreachable for any item with an Icon param, because the Icon
     * branch has already made normalTexture non-null. Leaving it null hands those items the FIRST
     * IconsForTexture entry instead -- `item ClubHammer` has `Icon = ClubHammer` and
     * `IconsForTexture = ClubHammer_Forged;ClubHammer`, and it came out as the forged icon.
     *
     * Two items in 12,768 differed, which no timing measurement would ever have shown. Restoring
     * null here re-defers exactly the items we deferred; items with no Icon param have a null
     * itemName, are untouched, and keep the engine's fallback.
     */
    @Patch(className = "zombie.scripting.objects.Item", methodName = "InitLoadPP")
    public static class PostParse {
        @Patch.OnExit
        public static void exit(@Patch.This Item item) {
            if (LazyIcon.ON && !LazyIcon.off) {
                LazyIcon.postParse(item);
            }
        }
    }

    /**
     * OnExit rather than a skipping OnEnter: the engine method returns a value, and rewriting a
     * null return is both smaller and impossible to get half-right.
     */
    @Patch(className = "zombie.scripting.objects.Item", methodName = "getNormalTexture")
    public static class Getter {
        @Patch.OnExit
        public static void exit(@Patch.This Item item,
                                @Patch.Return(readOnly = false) Texture ret) {
            ret = LazyIcon.resolve(item);
        }
    }

    /**
     * The three direct reads of Item.normalTexture are in constructors, which advice does not
     * reach. They all copy the field into InventoryItem.texture, and everything that draws an
     * inventory icon goes through getTexture() -- so resolving here covers all three, and does it
     * before anything binds the texture.
     */
    @Patch(className = "zombie.inventory.InventoryItem", methodName = "getTexture")
    public static class ItemTexture {
        @Patch.OnExit
        public static void exit(@Patch.This Object self,
                                @Patch.Return(readOnly = false) Texture ret) {
            if (ret == null) {
                ret = LazyIcon.resolveFor(self);
            }
        }
    }
}
