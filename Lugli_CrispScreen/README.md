# Lugli - Crisp Screen

The game puts a slight blur over the whole screen before you see it. This mod turns that off, so
you see the game as sharp as it's actually drawn, with a little sharpening on top.

No dependencies. Enable it and restart the game.

## How it works

The blur comes from the last shader the game runs, `media/shaders/screen.frag`, which samples the
finished world image with a bicubic filter. That pass maps the image one to one onto the screen
(zoom is applied earlier), so the filter only softens it.

The mod ships the game's own `screen.frag` with one change: that sample reads the exact pixel
instead, then applies a light contrast-adaptive sharpen. The sharpen is clamped to each pixel's
neighbours, so it can't create halos. Everything else in the file is vanilla, so lighting, colours,
night, fog, rain, film grain and the drunk, short-sighted, search-mode and night-vision effects
work as usual.

The added code only uses what the game's older shader version supports, so it also runs on graphics
drivers without OpenGL 3.3, where the game falls back to that version.

## Compatibility

- Any other mod that replaces `media/shaders/screen.frag` (ShaderZ, for example) conflicts with this
  one. Whichever loads last wins, so keep just one.
- It only changes how things look and saves nothing, so you can add or remove it from an existing save.
- Restart the game after enabling or disabling it, since the screen shader is built once per session.

## Game updates

When an update changes the vanilla shader, the mod gets rebuilt from the new one. An old copy would
quietly undo whatever the update changed, so keep the mod updated.

## Checking that it loaded

The console prints one line at boot:

```
[Lugli/CrispScreen] loaded [build <date> (<n> files)], 1 part(s): Shader: screen.frag from vanilla <hash>, sharpness <value>
```

`<hash>` names the vanilla shader the file was built from. The line shows the mod is active, but not
that the shader compiled, because the game doesn't report shader errors. If the screen looks as
blurry as before, another mod replaced `screen.frag` after this one.

## Credits

Thanks to [ShaderZ by Alree](https://steamcommunity.com/sharedfiles/filedetails/?id=3419026942) for
finding where the blur comes from. This one is written from scratch on top of the current vanilla
shader.

## Licence

MIT for the added code. The rest of the shipped shader is the game's own file.
