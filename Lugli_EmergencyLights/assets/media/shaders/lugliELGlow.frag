#version 110

// LugliEL fullbright: basicEffect with the lighting term removed.
//
// WHY THIS EXISTS. A burning glow stick has to look like it is burning, and under the stock
// shader it cannot. A ground item is rendered once into the world-item atlas and then blitted,
// and that atlas render runs basicEffect with AmbientColour 0.4 and one key light at 0.375
// (WorldItemAtlas.java:1476-1489), so `lighting` lands between 0.400 and 0.775. The blit then
// multiplies by the tile's own light and clamps at 1.0, so the object can never be brighter than
// the tile it lies on. The shipped green stick peaks near RGB(4,148,10): a dark saturated green,
// which reads as painted plastic no matter what is drawn around it.
//
// Dropping the lighting term makes the ceiling `texel * tint` instead of `texel * tint * 0.4..0.775`
// -- a gain of 1.3x to 2.5x -- and it does it WITHOUT saturating, so the mesh's own shading
// survives and the three families still look like different objects.
//
// #version 110 with `varying`, paired with a #version 330 vertex shader using `out`. That looks
// wrong and is exactly what vanilla does: basicEffect.frag is 110 and basicEffect_static.vert is
// 330. The interface matches by name, so it links.
//
// THE UNIFORM NAMES ARE NOT FREE. The sampler must be `Texture` (Shader.java:278,
// WorldItemAtlas.java:1450) and the tint must be `TintColour` (Shader.java:147). Uniforms this
// shader does not declare are harmless -- every setter null-guards through
// ShaderProgram.setValue -- so the five lights and AmbientColour are simply absent.

varying vec3 vertColour;
varying vec3 vertNormal;
varying vec2 texCoords;

uniform sampler2D Texture;
uniform float Alpha;
uniform vec3 TintColour;

void main()
{
	vec4 texSample = texture2D(Texture, texCoords);

	if (texSample.w < 0.01)
	{
		discard;
	}

	// No lighting term at all: this is the whole difference from basicEffect.
	vec3 col = texSample.xyz * TintColour;

	gl_FragColor = vec4(Alpha * col * vertColour, Alpha * texSample.w);
}
