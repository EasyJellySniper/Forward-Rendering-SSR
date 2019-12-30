// Upgrade NOTE: replaced 'defined _USEVERTEXCOLOR' with 'defined (_USEVERTEXCOLOR)'

// Upgrade NOTE: replaced 'defined _USEGEOPASS' with 'defined (_USEGEOPASS)'

// Unity built-in shader source. Copyright (c) 2016 Unity Technologies. MIT license (see license.txt)

#ifndef IGS_STANDARD_CORE_INCLUDED
#define IGS_STANDARD_CORE_INCLUDED

#include "UnityCG.cginc"
#include "UnityShaderVariables.cginc"
#include "UnityInstancing.cginc"
#include "UnityStandardConfig.cginc"
#include "UnityStandardInput.cginc"
#include "UnityPBSLighting.cginc"
#include "UnityStandardUtils.cginc"
#include "UnityGBuffer.cginc"
#include "UnityStandardBRDF.cginc"
#include "AutoLight.cginc"
#include "IGSInclude.cginc"

//-------------------------------------------------------------------------------------
// counterpart for NormalizePerPixelNormal
// skips normalization per-vertex and expects normalization to happen per-pixel
half3 NormalizePerVertexNormal (float3 n) // takes float to avoid overflow
{
    #if (SHADER_TARGET < 30) || UNITY_STANDARD_SIMPLE
        return normalize(n);
    #else
        return n; // will normalize per-pixel instead
    #endif
}

//-------------------------------------------------------------------------------------
UnityLight MainLight ()
{
    UnityLight l;

    l.color = _LightColor0.rgb;
    l.dir = _WorldSpaceLightPos0.xyz;
    return l;
}

UnityLight AdditiveLight (half3 lightDir, half atten)
{
    UnityLight l;

    l.color = _LightColor0.rgb;
    l.dir = lightDir;
    #ifndef USING_DIRECTIONAL_LIGHT
        l.dir = NormalizePerPixelNormal(l.dir);
    #endif

    // shadow the light
    l.color *= atten;
    return l;
}

UnityLight DummyLight ()
{
    UnityLight l;
    l.color = 0;
    l.dir = half3 (0,1,0);
    return l;
}

UnityIndirect ZeroIndirect ()
{
    UnityIndirect ind;
    ind.diffuse = 0;
    ind.specular = 0;
    return ind;
}

//-------------------------------------------------------------------------------------
// Common fragment setup

// deprecated
half3 WorldNormal(half4 tan2world[3])
{
    return normalize(tan2world[2].xyz);
}

// deprecated
#ifdef _TANGENT_TO_WORLD
    half3x3 ExtractTangentToWorldPerPixel(half4 tan2world[3])
    {
        half3 t = tan2world[0].xyz;
        half3 b = tan2world[1].xyz;
        half3 n = tan2world[2].xyz;

    #if UNITY_TANGENT_ORTHONORMALIZE
        n = NormalizePerPixelNormal(n);

        // ortho-normalize Tangent
        t = normalize (t - n * dot(t, n));

        // recalculate Binormal
        half3 newB = cross(n, t);
        b = newB * sign (dot (newB, b));
    #endif

        return half3x3(t, b, n);
    }
#else
    half3x3 ExtractTangentToWorldPerPixel(half4 tan2world[3])
    {
        return half3x3(0,0,0,0,0,0,0,0,0);
    }
#endif

float3 PerPixelWorldNormal(float4 i_tex, float4 tangentToWorld[3], float bumpScale)
{

#ifdef _NORMALMAP

    half3 tangent = tangentToWorld[0].xyz;
    half3 binormal = tangentToWorld[1].xyz;
    half3 normal = tangentToWorld[2].xyz;

    #if UNITY_TANGENT_ORTHONORMALIZE
        normal = NormalizePerPixelNormal(normal);

        // ortho-normalize Tangent
        tangent = normalize (tangent - normal * dot(tangent, normal));

        // recalculate Binormal
        half3 newB = cross(normal, tangent);
        binormal = newB * sign (dot (newB, binormal));
    #endif

    half3 normalTangent = IGSNormalInTangentSpace(i_tex, bumpScale);
    float3 normalWorld = NormalizePerPixelNormal(tangent * normalTangent.x + binormal * normalTangent.y + normal * normalTangent.z); // @TODO: see if we can squeeze this normalize on SM2.0 as well
#else
    float3 normalWorld = normalize(tangentToWorld[2].xyz);
#endif
    return normalWorld;
}

#ifdef _PARALLAXMAP
    #define IN_VIEWDIR4PARALLAX(i) NormalizePerPixelNormal(half3(i.tangentToWorldAndPackedData[0].w,i.tangentToWorldAndPackedData[1].w,i.tangentToWorldAndPackedData[2].w))
    #define IN_VIEWDIR4PARALLAX_FWDADD(i) NormalizePerPixelNormal(i.viewDirForParallax.xyz)
#else
    #define IN_VIEWDIR4PARALLAX(i) half3(0,0,0)
    #define IN_VIEWDIR4PARALLAX_FWDADD(i) half3(0,0,0)
#endif

#if UNITY_REQUIRE_FRAG_WORLDPOS
    #if UNITY_PACK_WORLDPOS_WITH_TANGENT
        #define IN_WORLDPOS(i) half3(i.tangentToWorldAndPackedData[0].w,i.tangentToWorldAndPackedData[1].w,i.tangentToWorldAndPackedData[2].w)
    #else
        #define IN_WORLDPOS(i) i.posWorld
    #endif
    #define IN_WORLDPOS_FWDADD(i) i.posWorld
#else
    #define IN_WORLDPOS(i) half3(0,0,0)
    #define IN_WORLDPOS_FWDADD(i) half3(0,0,0)
#endif

#define IN_LIGHTDIR_FWDADD(i) half3(i.tangentToWorldAndLightDir[0].w, i.tangentToWorldAndLightDir[1].w, i.tangentToWorldAndLightDir[2].w)

#define FRAGMENT_SETUP(x, y, z) FragmentCommonData x = \
	FragmentSetup(i.tex, i.eyeVec, IN_VIEWDIR4PARALLAX(i), i.tangentToWorldAndPackedData, IN_WORLDPOS(i), y, z);

#define FRAGMENT_SETUP_FWDADD(x, y) FragmentCommonData x = \
	FragmentSetup(i.tex, i.eyeVec, IN_VIEWDIR4PARALLAX_FWDADD(i), i.tangentToWorldAndLightDir, IN_WORLDPOS_FWDADD(i), _BumpScale, y);

#ifndef UNITY_SETUP_BRDF_INPUT
    #define UNITY_SETUP_BRDF_INPUT SpecularSetup
#endif

inline FragmentCommonData SpecularSetup (float4 i_tex, fixed4 vColor)
{
    half4 specGloss = SpecularGloss(i_tex.xy);
    half3 specColor = specGloss.rgb;
    half smoothness = specGloss.a;

    half oneMinusReflectivity;
    half3 diffColor = EnergyConservationBetweenDiffuseAndSpecular (Albedo(i_tex), specColor, /*out*/ oneMinusReflectivity);

    FragmentCommonData o = (FragmentCommonData)0;
    o.diffColor = diffColor;
    o.specColor = specColor;
    o.oneMinusReflectivity = oneMinusReflectivity;
    o.smoothness = smoothness;
    return o;
}

inline FragmentCommonData RoughnessSetup(float4 i_tex, fixed4 vColor)
{
    half2 metallicGloss = MetallicRough(i_tex.xy);
    half metallic = metallicGloss.x;
    half smoothness = metallicGloss.y; // this is 1 minus the square root of real roughness m.

    half oneMinusReflectivity;
    half3 specColor;
    half3 diffColor = DiffuseAndSpecularFromMetallic(Albedo(i_tex), metallic, /*out*/ specColor, /*out*/ oneMinusReflectivity);

    FragmentCommonData o = (FragmentCommonData)0;
    o.diffColor = diffColor;
    o.specColor = specColor;
    o.oneMinusReflectivity = oneMinusReflectivity;
    o.smoothness = smoothness;
    return o;
}

inline FragmentCommonData MetallicSetup (float4 i_tex, fixed4 vColor)
{
	FragmentCommonData o = (FragmentCommonData)0;

    half2 metallicGloss = IGSMetallicGloss(i_tex.xy);

    half metallic = metallicGloss.x;
    half smoothness = metallicGloss.y; // this is 1 minus the square root of real roughness m.

    half oneMinusReflectivity;
    half3 specColor;
	o.albedo = IGSAlbedo(i_tex);

#ifdef _VERTEXCOLORBLEND
	// mix texture blend
	float4 albedo0 = _AlbedoBlend0.Sample(sampler_AlbedoBlend0, i_tex.xy);
	float4 albedo1 = _AlbedoBlend1.Sample(sampler_AlbedoBlend0, i_tex.xy);
	float4 albedo2 = _AlbedoBlend2.Sample(sampler_AlbedoBlend0, i_tex.xy);

	float smooth0 = albedo0.a;
	float smooth1 = albedo1.a;
	float smooth2 = albedo2.a;

	float3 blendColor = albedo0.rgb * vColor.r + albedo1.rgb * vColor.g + albedo2.rgb * vColor.b;
	float blendSmooth = smooth0 * vColor.r + smooth1 * vColor.g + smooth2 * vColor.b;
	float albedoRatio = (1 - vColor.r - vColor.g - vColor.b);

	o.albedo.rgb = o.albedo.rgb * albedoRatio + blendColor;
	smoothness = smoothness * albedoRatio + blendSmooth;
#endif

    half3 diffColor = DiffuseAndSpecularFromMetallic(o.albedo, metallic, /*out*/ specColor, /*out*/ oneMinusReflectivity);

    o.diffColor = diffColor;
    o.specColor = specColor * _CustomSpecColor.rgb;
    o.oneMinusReflectivity = oneMinusReflectivity;
    o.smoothness = smoothness;
    return o;
}

// parallax transformed texcoord is used to sample occlusion
inline FragmentCommonData FragmentSetup (inout float4 i_tex, float3 i_eyeVec, half3 i_viewDirForParallax, float4 tangentToWorld[3], float3 i_posWorld, float bumpScale, fixed4 vColor)
{
    i_tex = Parallax(i_tex, i_viewDirForParallax);

    half alpha = Alpha(i_tex.xy);
    #if defined(_ALPHATEST_ON)
        clip (alpha - _Cutoff);
    #endif

    FragmentCommonData o = UNITY_SETUP_BRDF_INPUT (i_tex, vColor);
    o.normalWorld = PerPixelWorldNormal(i_tex, tangentToWorld, bumpScale);
    o.eyeVec = NormalizePerPixelNormal(i_eyeVec);
    o.posWorld = i_posWorld;

    // NOTE: shader relies on pre-multiply alpha-blend (_SrcBlend = One, _DstBlend = OneMinusSrcAlpha)
    o.diffColor = PreMultiplyAlpha (o.diffColor, alpha, o.oneMinusReflectivity, /*out*/ o.alpha);
    return o;
}

inline UnityGI FragmentGI (FragmentCommonData s, half occlusion, half4 i_ambientOrLightmapUV, half atten, UnityLight light, bool reflections)
{
    UnityGIInput d;
    d.light = light;
    d.worldPos = s.posWorld;
    d.worldViewDir = -s.eyeVec;
    d.atten = atten;
    #if defined(LIGHTMAP_ON) || defined(DYNAMICLIGHTMAP_ON)
        d.ambient = 0;
        d.lightmapUV = i_ambientOrLightmapUV;
    #else
        d.ambient = i_ambientOrLightmapUV.rgb;
        d.lightmapUV = 0;
    #endif

    d.probeHDR[0] = unity_SpecCube0_HDR;
    d.probeHDR[1] = unity_SpecCube1_HDR;
    #if defined(UNITY_SPECCUBE_BLENDING) || defined(UNITY_SPECCUBE_BOX_PROJECTION)
      d.boxMin[0] = unity_SpecCube0_BoxMin; // .w holds lerp value for blending
    #endif
    #ifdef UNITY_SPECCUBE_BOX_PROJECTION
      d.boxMax[0] = unity_SpecCube0_BoxMax;
      d.probePosition[0] = unity_SpecCube0_ProbePosition;
      d.boxMax[1] = unity_SpecCube1_BoxMax;
      d.boxMin[1] = unity_SpecCube1_BoxMin;
      d.probePosition[1] = unity_SpecCube1_ProbePosition;
    #endif

    if(reflections)
    {
        Unity_GlossyEnvironmentData g = UnityGlossyEnvironmentSetup(s.smoothness, -s.eyeVec, s.normalWorld, s.specColor);
        // Replace the reflUVW if it has been compute in Vertex shader. Note: the compiler will optimize the calcul in UnityGlossyEnvironmentSetup itself
        #if UNITY_STANDARD_SIMPLE
            g.reflUVW = s.reflUVW;
        #endif

        return UnityGlobalIllumination(d, occlusion, s.normalWorld, g);
    }
    else
    {
        return UnityGlobalIllumination (d, occlusion, s.normalWorld);
    }
}

inline UnityGI FragmentGI (FragmentCommonData s, half occlusion, half4 i_ambientOrLightmapUV, half atten, UnityLight light)
{
    return FragmentGI(s, occlusion, i_ambientOrLightmapUV, atten, light, true);
}


//-------------------------------------------------------------------------------------
half4 OutputForward (half4 output, half alphaFromSurface)
{
    #if defined(_ALPHABLEND_ON) || defined(_ALPHAPREMULTIPLY_ON)
        output.a = alphaFromSurface;
    #else
        UNITY_OPAQUE_ALPHA(output.a);
    #endif
    return output;
}

inline half4 VertexGIForward(VertexInput v, float3 posWorld, half3 normalWorld)
{
    half4 ambientOrLightmapUV = 0;
    // Static lightmaps
    #ifdef LIGHTMAP_ON
        ambientOrLightmapUV.xy = v.uv1.xy * unity_LightmapST.xy + unity_LightmapST.zw;
        ambientOrLightmapUV.zw = 0;
    // Sample light probe for Dynamic objects only (no static or dynamic lightmaps)
    #elif UNITY_SHOULD_SAMPLE_SH
        #ifdef VERTEXLIGHT_ON
            // Approximated illumination from non-important point lights
            ambientOrLightmapUV.rgb = Shade4PointLights (
                unity_4LightPosX0, unity_4LightPosY0, unity_4LightPosZ0,
                unity_LightColor[0].rgb, unity_LightColor[1].rgb, unity_LightColor[2].rgb, unity_LightColor[3].rgb,
                unity_4LightAtten0, posWorld, normalWorld);
        #endif

        ambientOrLightmapUV.rgb = ShadeSHPerVertex (normalWorld, ambientOrLightmapUV.rgb);
    #endif

    #ifdef DYNAMICLIGHTMAP_ON
        ambientOrLightmapUV.zw = v.uv2.xy * unity_DynamicLightmapST.xy + unity_DynamicLightmapST.zw;
    #endif

    return ambientOrLightmapUV;
}

inline half4 VertexGIForwardTess(float2 uv1, float2 uv2 , float3 posWorld, half3 normalWorld)
{
	half4 ambientOrLightmapUV = 0;
	// Static lightmaps
#ifdef LIGHTMAP_ON
	ambientOrLightmapUV.xy = uv1.xy * unity_LightmapST.xy + unity_LightmapST.zw;
	ambientOrLightmapUV.zw = 0;
	// Sample light probe for Dynamic objects only (no static or dynamic lightmaps)
#elif UNITY_SHOULD_SAMPLE_SH
#ifdef VERTEXLIGHT_ON
	// Approximated illumination from non-important point lights
	ambientOrLightmapUV.rgb = Shade4PointLights(
		unity_4LightPosX0, unity_4LightPosY0, unity_4LightPosZ0,
		unity_LightColor[0].rgb, unity_LightColor[1].rgb, unity_LightColor[2].rgb, unity_LightColor[3].rgb,
		unity_4LightAtten0, posWorld, normalWorld);
#endif

	ambientOrLightmapUV.rgb = ShadeSHPerVertex(normalWorld, ambientOrLightmapUV.rgb);
#endif

#ifdef DYNAMICLIGHTMAP_ON
	ambientOrLightmapUV.zw = uv2.xy * unity_DynamicLightmapST.xy + unity_DynamicLightmapST.zw;
#endif

	return ambientOrLightmapUV;
}

// ------------------------------------------------------------------
//  Base forward pass (directional light, emission, lightmaps, ...)

struct VertexOutputForwardBase
{
	fixed4 color : COLOR0;

    UNITY_POSITION(pos);
    float4 tex                            : TEXCOORD0;
    float3 eyeVec                         : TEXCOORD1;
    float4 tangentToWorldAndPackedData[3] : TEXCOORD2;    // [3x3:tangentToWorld | 1x3:viewDirForParallax or worldPos]
    half4 ambientOrLightmapUV             : TEXCOORD5;    // SH or Lightmap UV
	UNITY_SHADOW_COORDS(6)

#ifndef _USEGEOPASS
	UNITY_FOG_COORDS(7)
#endif

    // next ones would not fit into SM2.0 limits, but they are always for SM3.0+
    #if UNITY_REQUIRE_FRAG_WORLDPOS && !UNITY_PACK_WORLDPOS_WITH_TANGENT
        float3 posWorld                 : TEXCOORD8;
    #endif

	float2 uv0 : TEXCOORD9;

	uint targetIdx : TARGETIDX;
    UNITY_VERTEX_INPUT_INSTANCE_ID
    UNITY_VERTEX_OUTPUT_STEREO
};

struct GeometryOutputForwardBase
{
	fixed4 color : COLOR0;

	UNITY_POSITION(pos);
	float4 tex                            : TEXCOORD0;
	float3 eyeVec                         : TEXCOORD1;
	float4 tangentToWorldAndPackedData[3] : TEXCOORD2;    // [3x3:tangentToWorld | 1x3:viewDirForParallax or worldPos]
	half4 ambientOrLightmapUV             : TEXCOORD5;    // SH or Lightmap UV
	UNITY_SHADOW_COORDS(6)

#ifndef _USEGEOPASS
	UNITY_FOG_COORDS(7)
#endif

	// next ones would not fit into SM2.0 limits, but they are always for SM3.0+
	#if UNITY_REQUIRE_FRAG_WORLDPOS && !UNITY_PACK_WORLDPOS_WITH_TANGENT
		float3 posWorld                 : TEXCOORD8;
	#endif

	float2 uv0 : TEXCOORD9;

	uint targetIdx : SV_RenderTargetArrayIndex;

#if defined(UNITY_INSTANCING_ENABLED)
	uint instanceID : InstanceID;
#endif

	UNITY_VERTEX_OUTPUT_STEREO
};

VertexOutputForwardBase vertForwardBase (VertexInput v, half4 color : COLOR)
{
    UNITY_SETUP_INSTANCE_ID(v);
    VertexOutputForwardBase o;
    UNITY_INITIALIZE_OUTPUT(VertexOutputForwardBase, o);
    UNITY_TRANSFER_INSTANCE_ID(v, o);
    UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);

	o.color = color;

    float4 posWorld = mul(unity_ObjectToWorld, v.vertex);
    #if UNITY_REQUIRE_FRAG_WORLDPOS
        #if UNITY_PACK_WORLDPOS_WITH_TANGENT
            o.tangentToWorldAndPackedData[0].w = posWorld.x;
            o.tangentToWorldAndPackedData[1].w = posWorld.y;
            o.tangentToWorldAndPackedData[2].w = posWorld.z;
        #else
            o.posWorld = posWorld.xyz;
        #endif
    #endif

	o.pos = UnityObjectToClipPos(v.vertex);
	UNITY_TRANSFER_SHADOW(o, v.uv1);

	#if defined (_USEGEOPASS)
		o.pos = posWorld;				// only output world pos here since we want geometry shader pass
	#endif

	o.uv0 = v.uv0;
    o.tex = TexCoords(v);

    o.eyeVec = NormalizePerVertexNormal(posWorld.xyz - _WorldSpaceCameraPos);
    float3 normalWorld = UnityObjectToWorldNormal(v.normal);

    #ifdef _TANGENT_TO_WORLD

		float4 tangentWorld = float4(UnityObjectToWorldDir(v.tangent.xyz), v.tangent.w);

        float3x3 tangentToWorld = CreateTangentToWorldPerVertex(normalWorld, tangentWorld.xyz, tangentWorld.w);
        o.tangentToWorldAndPackedData[0].xyz = tangentToWorld[0];
        o.tangentToWorldAndPackedData[1].xyz = tangentToWorld[1];
        o.tangentToWorldAndPackedData[2].xyz = tangentToWorld[2];
    #else
        o.tangentToWorldAndPackedData[0].xyz = 0;
        o.tangentToWorldAndPackedData[1].xyz = 0;
        o.tangentToWorldAndPackedData[2].xyz = normalWorld;
    #endif

    o.ambientOrLightmapUV = VertexGIForward(v, posWorld, normalWorld);

    #ifdef _PARALLAXMAP
		TANGENT_SPACE_ROTATION;

        half3 viewDirForParallax = mul (rotation, ObjSpaceViewDir(v.vertex));
        o.tangentToWorldAndPackedData[0].w = viewDirForParallax.x;
        o.tangentToWorldAndPackedData[1].w = viewDirForParallax.y;
        o.tangentToWorldAndPackedData[2].w = viewDirForParallax.z;
    #endif

#ifndef _USEGEOPASS
    UNITY_TRANSFER_FOG(o,o.pos);
#endif
    return o;
}

// output 4 faces one frame
[maxvertexcount(12)]
void geoForwardBase(triangle VertexOutputForwardBase input[3], inout TriangleStream<GeometryOutputForwardBase> TriStream)
{
	uint renderToFace[6] = { 0,0,0,0,0,0 };

	[unroll]
	for (uint i = 0; i < 6; i++)
	{
		GeometryOutputForwardBase o;
		uint insideCounter = 0;

		[unroll]
		for (uint j = 0; j < 3; j++)
		{
			o = input[j];
			insideCounter += InsideCubeMap(o.pos.xyz, i);
		}

		[branch]
		if (insideCounter > 0)
		{
			renderToFace[i] = 1;
		}
	}

	[unroll]
	for (i = 0; i < 6; i++)
	{
		GeometryOutputForwardBase o;

		[branch]
		if (renderToFace[i] == 1 && _UpdateFace[i] == 1)
		{
			[unroll]
			for (uint j = 0; j < 3; j++)
			{
				o = input[j];

				o.pos = mul(_CubeMapView[i], input[j].pos);
				o.pos = mul(_CubeMapProj[i], o.pos);
				o.targetIdx = i;

				TriStream.Append(o);
			}
			TriStream.RestartStrip();
		}
	}
}

float4 TexCoordsTess(float2 uv0, float2 uv1)
{
	float4 texcoord;
	texcoord.xy = TRANSFORM_TEX(uv0, _MainTex); // Always source from uv0
	texcoord.zw = TRANSFORM_TEX(((_UVSec == 0) ? uv0 : uv1), _DetailAlbedoMap);
	return texcoord;
}

half4 fragForwardBaseInternal (VertexOutputForwardBase i, inout half4 colorRT, inout half4 specularRT, inout half4 normalRT)
{
    UNITY_APPLY_DITHER_CROSSFADE(i.pos.xy);

#if defined(_VERTEXCOLORBLEND)
	FRAGMENT_SETUP(s, _BumpScale, i.color)
#else
	FRAGMENT_SETUP(s, _BumpScale, 0)
#endif

    UNITY_SETUP_INSTANCE_ID(i);
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);

	// modify smooth value according to reflection mask
	float reflMask = IGSReflectionMask(i.uv0, s.alpha, s.smoothness);

    UnityLight mainLight = MainLight ();

    UNITY_LIGHT_ATTENUATION(atten, i, s.posWorld);

#if (defined(_ALPHABLEND_ON) || defined(_ALPHAPREMULTIPLY_ON))
	[branch]
	if(_ReceiveTransparentShadow == 1.0f)
		atten *= IGSShadowAtten(s);
#elif defined(_USEGEOPASS) && !defined(SHADOWS_SHADOWMASK)
	atten *= IGSShadowAtten(s);
#endif

    half occlusion = IGSOcclusion(i.tex.xy);
    UnityGI gi = FragmentGI (s, occlusion, i.ambientOrLightmapUV, atten, mainLight);
	
	gi.indirect.specular *= reflMask;

	// igs reflection
	float4 refl = IGSReflection(s, reflMask);
	gi.indirect.specular = lerp(gi.indirect.specular, 0, refl.a);
#ifdef _CUBEMAP
	gi.indirect.specular = 0;
#endif
	gi.indirect.specular += clamp(refl.rgb, 0, 99);

    half4 c = UNITY_BRDF_PBS (s.diffColor, s.specColor, s.oneMinusReflectivity, s.smoothness, s.normalWorld, -s.eyeVec, gi.light, gi.indirect);
    c.rgb += IGSEmission(i.tex.xy, s.alpha, s.albedo);

	colorRT = half4(s.diffColor, occlusion);
	specularRT = half4(s.specColor.rgb, s.smoothness);
	normalRT = half4(s.normalWorld.xyz * 0.5f + 0.5f, 1.0f);

#ifndef _USEGEOPASS
	UNITY_APPLY_FOG(i.fogCoord, c.rgb);
#endif
    return OutputForward (c, s.alpha);
}

half4 fragForwardBase (VertexOutputForwardBase i
, inout half4 colorRT : SV_Target1
, inout half4 specularRT : SV_Target2
, inout half4 normalRT : SV_Target3) : SV_Target0  // backward compatibility (this used to be the fragment entry function)
{
    return fragForwardBaseInternal(i, colorRT, specularRT, normalRT);
}

// ------------------------------------------------------------------
//  Additive forward pass (one light per pass)

struct VertexOutputForwardAdd
{
	fixed4 color : COLOR0;

    UNITY_POSITION(pos);
    float4 tex                          : TEXCOORD0;
    float3 eyeVec                       : TEXCOORD1;
    float4 tangentToWorldAndLightDir[3] : TEXCOORD2;    // [3x3:tangentToWorld | 1x3:lightDir]
    float3 posWorld                     : TEXCOORD5;
    UNITY_SHADOW_COORDS(6)
    UNITY_FOG_COORDS(7)

    // next ones would not fit into SM2.0 limits, but they are always for SM3.0+
#if defined(_PARALLAXMAP)
    half3 viewDirForParallax            : TEXCOORD8;
#endif

    UNITY_VERTEX_OUTPUT_STEREO
};

VertexOutputForwardAdd vertForwardAdd (VertexInput v, half4 color : COLOR)
{
    UNITY_SETUP_INSTANCE_ID(v);
    VertexOutputForwardAdd o;
    UNITY_INITIALIZE_OUTPUT(VertexOutputForwardAdd, o);
    UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);

	o.color = color;

    float4 posWorld = mul(unity_ObjectToWorld, v.vertex);
    o.pos = UnityObjectToClipPos(v.vertex);

    o.tex = TexCoords(v);
    o.eyeVec = NormalizePerVertexNormal(posWorld.xyz - _WorldSpaceCameraPos);
    o.posWorld = posWorld.xyz;
    float3 normalWorld = UnityObjectToWorldNormal(v.normal);

    #ifdef _TANGENT_TO_WORLD

		float4 tangentWorld = float4(UnityObjectToWorldDir(v.tangent.xyz), v.tangent.w);

        float3x3 tangentToWorld = CreateTangentToWorldPerVertex(normalWorld, tangentWorld.xyz, tangentWorld.w);
        o.tangentToWorldAndLightDir[0].xyz = tangentToWorld[0];
        o.tangentToWorldAndLightDir[1].xyz = tangentToWorld[1];
        o.tangentToWorldAndLightDir[2].xyz = tangentToWorld[2];
    #else
        o.tangentToWorldAndLightDir[0].xyz = 0;
        o.tangentToWorldAndLightDir[1].xyz = 0;
        o.tangentToWorldAndLightDir[2].xyz = normalWorld;
    #endif
    //We need this for shadow receiving
    UNITY_TRANSFER_SHADOW(o, v.uv1);

    float3 lightDir = _WorldSpaceLightPos0.xyz - posWorld.xyz * _WorldSpaceLightPos0.w;
    #ifndef USING_DIRECTIONAL_LIGHT
        lightDir = NormalizePerVertexNormal(lightDir);
    #endif
    o.tangentToWorldAndLightDir[0].w = lightDir.x;
    o.tangentToWorldAndLightDir[1].w = lightDir.y;
    o.tangentToWorldAndLightDir[2].w = lightDir.z;

    #ifdef _PARALLAXMAP
		TANGENT_SPACE_ROTATION;
        o.viewDirForParallax = mul (rotation, ObjSpaceViewDir(v.vertex));
    #endif

    UNITY_TRANSFER_FOG(o,o.pos);
    return o;
}

half4 fragForwardAddInternal (VertexOutputForwardAdd i)
{
    UNITY_APPLY_DITHER_CROSSFADE(i.pos.xy);

#if defined(_VERTEXCOLORBLEND)
    FRAGMENT_SETUP_FWDADD(s, i.color)
#else
	FRAGMENT_SETUP_FWDADD(s, 0)
#endif

    UNITY_LIGHT_ATTENUATION(atten, i, s.posWorld)
    UnityLight light = AdditiveLight (IN_LIGHTDIR_FWDADD(i), atten);
    UnityIndirect noIndirect = ZeroIndirect ();

    half4 c = UNITY_BRDF_PBS (s.diffColor, s.specColor, s.oneMinusReflectivity, s.smoothness, s.normalWorld, -s.eyeVec, light, noIndirect);

    UNITY_APPLY_FOG_COLOR(i.fogCoord, c.rgb, half4(0,0,0,0)); // fog towards black in additive pass

    return OutputForward (c, s.alpha);
}

half4 fragForwardAdd (VertexOutputForwardAdd i) : SV_Target     // backward compatibility (this used to be the fragment entry function)
{
    return fragForwardAddInternal(i);
}

// ------------------------------------------------------------------
//  Deferred pass

struct VertexOutputDeferred
{
	fixed4 color : COLOR0;

    UNITY_POSITION(pos);
    float4 tex                            : TEXCOORD0;
    float3 eyeVec                         : TEXCOORD1;
    float4 tangentToWorldAndPackedData[3] : TEXCOORD2;    // [3x3:tangentToWorld | 1x3:viewDirForParallax or worldPos]
    half4 ambientOrLightmapUV             : TEXCOORD5;    // SH or Lightmap UVs

    #if UNITY_REQUIRE_FRAG_WORLDPOS && !UNITY_PACK_WORLDPOS_WITH_TANGENT
        float3 posWorld                     : TEXCOORD6;
    #endif

	float2 uv0 : TEXCOORD7;
	float2 uv1 : TEXCOORD9;

	UNITY_VERTEX_INPUT_INSTANCE_ID
    UNITY_VERTEX_OUTPUT_STEREO
};

// simple deferred用於遠處物件
VertexOutputDeferred vertDeferredSimple(VertexInput v)
{
	UNITY_SETUP_INSTANCE_ID(v);

	VertexOutputDeferred o = (VertexOutputDeferred)0;
	o.pos = UnityObjectToClipPos(v.vertex);
	o.tex.xy = TRANSFORM_TEX(v.uv0, _MainTex);
	o.tangentToWorldAndPackedData[2].xyz = UnityObjectToWorldNormal(v.normal);

	o.ambientOrLightmapUV = 0;
	#ifdef LIGHTMAP_ON
		o.ambientOrLightmapUV.xy = v.uv1.xy * unity_LightmapST.xy + unity_LightmapST.zw;
	#elif UNITY_SHOULD_SAMPLE_SH
		o.ambientOrLightmapUV.rgb = ShadeSHPerVertex(o.tangentToWorldAndPackedData[2].xyz, o.ambientOrLightmapUV.rgb);
	#endif

	UNITY_TRANSFER_INSTANCE_ID(v, o);
	return o;
}

// simple deferred用於遠處物件
void fragDeferredSimple(VertexOutputDeferred i,
	out half4 outGBuffer0,
	out half4 outGBuffer1,
	out half4 outGBuffer2,
	out half4 outEmission          // RT3: emission (rgb), --unused-- (a)
#if defined(SHADOWS_SHADOWMASK) && (UNITY_ALLOWED_MRT_COUNT > 4)
	, out half4 outShadowMask       // RT4: shadowmask (rgba)
#endif
)
{
	UNITY_SETUP_INSTANCE_ID(i);

	// fill diffuse buffer, assume no occlusion
	float4 col = tex2D(_MainTex, i.tex.xy) * _Color;
#if _ALPHATEST_ON
	clip(col.a - _Cutoff);
#endif

	half oneMinusReflectivity;
	half3 specColor;
	col.rgb = DiffuseAndSpecularFromMetallic(col.rgb, tex2D(_MetallicGlossMap, i.tex.xy).r * _Metallic, /*out*/ specColor, /*out*/ oneMinusReflectivity);

	outGBuffer0.rgb = col.rgb;
	outGBuffer0.a = 1;

	// fill specular buffer, simple specular
	outGBuffer1.rgb = specColor * _CustomSpecColor.rgb;
	outGBuffer1.a = _Glossiness;

	// fill normal buffer, vertex normal only, assume doesn't use specular high light
	outGBuffer2.rgb = i.tangentToWorldAndPackedData[2].xyz * 0.5f + 0.5f;
	outGBuffer2.a = 0;

	// ignore emission, simple mix color and specular
	outEmission.rgb = (outGBuffer0.rgb + outGBuffer1.rgb) * 0.5f;
	outEmission.a = 1;

	// sample shadow mask
#if defined(SHADOWS_SHADOWMASK) && (UNITY_ALLOWED_MRT_COUNT > 4)
	outShadowMask = UnityGetRawBakedOcclusions(i.ambientOrLightmapUV.xy, half3(0, 0, 0));
#endif
}


VertexOutputDeferred vertDeferred (VertexInput v, half4 color : COLOR)
{
    UNITY_SETUP_INSTANCE_ID(v);
    VertexOutputDeferred o;
    UNITY_INITIALIZE_OUTPUT(VertexOutputDeferred, o);
	UNITY_TRANSFER_INSTANCE_ID(v, o);
    UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);

	o.color = color;

    float4 posWorld = mul(unity_ObjectToWorld, v.vertex);
	o.eyeVec = NormalizePerVertexNormal(posWorld.xyz - _WorldSpaceCameraPos);

#if UNITY_REQUIRE_FRAG_WORLDPOS
	#if UNITY_PACK_WORLDPOS_WITH_TANGENT
		o.tangentToWorldAndPackedData[0].w = posWorld.x;
		o.tangentToWorldAndPackedData[1].w = posWorld.y;
		o.tangentToWorldAndPackedData[2].w = posWorld.z;
	#else
		o.posWorld = posWorld.xyz;
	#endif
#endif

#if defined(_SHADERLOD)
	[branch]
	if (length(posWorld.xyz - _WorldSpaceCameraPos) > _IgsDistLod)
	{
		return vertDeferredSimple(v);
	}
#endif

    o.pos = UnityObjectToClipPos(v.vertex);

	o.uv0 = v.uv0;
    o.tex = TexCoords(v);

    float3 normalWorld = UnityObjectToWorldNormal(v.normal);

    #ifdef _TANGENT_TO_WORLD

		float4 tangentWorld = float4(UnityObjectToWorldDir(v.tangent.xyz), v.tangent.w);

        float3x3 tangentToWorld = CreateTangentToWorldPerVertex(normalWorld, tangentWorld.xyz, tangentWorld.w);
        o.tangentToWorldAndPackedData[0].xyz = tangentToWorld[0];
        o.tangentToWorldAndPackedData[1].xyz = tangentToWorld[1];
        o.tangentToWorldAndPackedData[2].xyz = tangentToWorld[2];
    #else
        o.tangentToWorldAndPackedData[0].xyz = 0;
        o.tangentToWorldAndPackedData[1].xyz = 0;
        o.tangentToWorldAndPackedData[2].xyz = normalWorld;
    #endif

    o.ambientOrLightmapUV = 0;
    #ifdef LIGHTMAP_ON
        o.ambientOrLightmapUV.xy = v.uv1.xy * unity_LightmapST.xy + unity_LightmapST.zw;
    #elif UNITY_SHOULD_SAMPLE_SH
        o.ambientOrLightmapUV.rgb = ShadeSHPerVertex (normalWorld, o.ambientOrLightmapUV.rgb);
    #endif
    #ifdef DYNAMICLIGHTMAP_ON
        o.ambientOrLightmapUV.zw = v.uv2.xy * unity_DynamicLightmapST.xy + unity_DynamicLightmapST.zw;
    #endif

    #ifdef _PARALLAXMAP

		TANGENT_SPACE_ROTATION;

        half3 viewDirForParallax = mul (rotation, ObjSpaceViewDir(v.vertex));
        o.tangentToWorldAndPackedData[0].w = viewDirForParallax.x;
        o.tangentToWorldAndPackedData[1].w = viewDirForParallax.y;
        o.tangentToWorldAndPackedData[2].w = viewDirForParallax.z;
    #endif

    return o;
}

void fragDeferred (
    VertexOutputDeferred i,
    out half4 outGBuffer0 : SV_Target0,
    out half4 outGBuffer1 : SV_Target1,
    out half4 outGBuffer2 : SV_Target2,
    out half4 outEmission : SV_Target3          // RT3: emission (rgb), --unused-- (a)
#if defined(SHADOWS_SHADOWMASK) && (UNITY_ALLOWED_MRT_COUNT > 4)
    ,out half4 outShadowMask : SV_Target4       // RT4: shadowmask (rgba)
#endif
)
{
    #if (SHADER_TARGET < 30)
        outGBuffer0 = 1;
        outGBuffer1 = 1;
        outGBuffer2 = 0;
        outEmission = 0;
        #if defined(SHADOWS_SHADOWMASK) && (UNITY_ALLOWED_MRT_COUNT > 4)
            outShadowMask = 1;
        #endif
        return;
    #endif

#if defined(_SHADERLOD)
	[branch]
	if (length(IN_WORLDPOS(i) - _WorldSpaceCameraPos) > _IgsDistLod)
	{
		fragDeferredSimple(i, outGBuffer0, outGBuffer1, outGBuffer2, outEmission
#if defined(SHADOWS_SHADOWMASK) && (UNITY_ALLOWED_MRT_COUNT > 4)
		, outShadowMask
#endif
		);
		return; 
	}
#endif

    UNITY_APPLY_DITHER_CROSSFADE(i.pos.xy);

#if defined(_VERTEXCOLORBLEND)
	FRAGMENT_SETUP(s, _BumpScale, i.color)
#else
	FRAGMENT_SETUP(s, _BumpScale, 0)
#endif

	UNITY_SETUP_INSTANCE_ID(i);

	// modify smooth value according to reflection mask
	float reflMask = IGSReflectionMask(i.uv0, s.alpha, s.smoothness);

    // no analytic lights in this pass
    UnityLight dummyLight = DummyLight ();
    half atten = 1;

    // only GI
    half occlusion = IGSOcclusion(i.tex.xy);
#if UNITY_ENABLE_REFLECTION_BUFFERS
    bool sampleReflectionsInDeferred = false;
#else
    bool sampleReflectionsInDeferred = true;
#endif

    UnityGI gi = FragmentGI (s, occlusion, i.ambientOrLightmapUV, atten, dummyLight, sampleReflectionsInDeferred);
	gi.indirect.specular *= reflMask;

	// igs reflection
	float4 refl = IGSReflection(s, reflMask);
	gi.indirect.specular = lerp(gi.indirect.specular, 0, refl.a);
#ifdef _CUBEMAP
	gi.indirect.specular = 0;
#endif
	gi.indirect.specular += clamp(refl.rgb, 0, 99);

    half3 emissiveColor = UNITY_BRDF_PBS (s.diffColor, s.specColor, s.oneMinusReflectivity, s.smoothness, s.normalWorld, -s.eyeVec, gi.light, gi.indirect).rgb;

    #ifdef _EMISSION
		emissiveColor += IGSEmission(i.tex.xy, s.alpha, s.albedo);
    #endif

    #ifndef UNITY_HDR_ON
        emissiveColor.rgb = exp2(-emissiveColor.rgb);
    #endif

    UnityStandardData data;
    data.diffuseColor   = s.diffColor;
    data.occlusion      = occlusion;
    data.specularColor  = s.specColor;
    data.smoothness     = s.smoothness;
    data.normalWorld    = s.normalWorld;

    UnityStandardDataToGbuffer(data, outGBuffer0, outGBuffer1, outGBuffer2);

#if defined(_SPECULARHIGHLIGHTS_OFF)
	outGBuffer2.a = 0;
#else
	outGBuffer2.a = 1;
#endif

    // Emissive lighting buffer
    outEmission = half4(emissiveColor, 1);

    // Baked direct lighting occlusion if any
    #if defined(SHADOWS_SHADOWMASK) && (UNITY_ALLOWED_MRT_COUNT > 4)
        outShadowMask = UnityGetRawBakedOcclusions(i.ambientOrLightmapUV.xy, IN_WORLDPOS(i));
    #endif

	// consider reflection mask
	outGBuffer1 *= reflMask.r;
}

//
// Old FragmentGI signature. Kept only for backward compatibility and will be removed soon
//

inline UnityGI FragmentGI(
    float3 posWorld,
    half occlusion, half4 i_ambientOrLightmapUV, half atten, half smoothness, half3 normalWorld, half3 eyeVec,
    UnityLight light,
    bool reflections)
{
    // we init only fields actually used
    FragmentCommonData s = (FragmentCommonData)0;
    s.smoothness = smoothness;
    s.normalWorld = normalWorld;
    s.eyeVec = eyeVec;
    s.posWorld = posWorld;
    return FragmentGI(s, occlusion, i_ambientOrLightmapUV, atten, light, reflections);
}
inline UnityGI FragmentGI (
    float3 posWorld,
    half occlusion, half4 i_ambientOrLightmapUV, half atten, half smoothness, half3 normalWorld, half3 eyeVec,
    UnityLight light)
{
    return FragmentGI (posWorld, occlusion, i_ambientOrLightmapUV, atten, smoothness, normalWorld, eyeVec, light, true);
}

#endif // IGS_STANDARD_CORE_INCLUDED
