// Unity built-in shader source. Copyright (c) 2016 Unity Technologies. MIT license (see license.txt)

#ifndef UNITY_STANDARD_CORE_FORWARD_INCLUDED
#define UNITY_STANDARD_CORE_FORWARD_INCLUDED

#if defined(UNITY_NO_FULL_STANDARD_SHADER)
#   define UNITY_STANDARD_SIMPLE 1
#endif

#include "UnityStandardConfig.cginc"

#if UNITY_STANDARD_SIMPLE
    #include "UnityStandardCoreForwardSimple.cginc"
    VertexOutputBaseSimple vertBase (VertexInput v) { return vertForwardBaseSimple(v); }
    VertexOutputForwardAddSimple vertAdd (VertexInput v) { return vertForwardAddSimple(v); }
    half4 fragBase (VertexOutputBaseSimple i) : SV_Target { return fragForwardBaseSimpleInternal(i); }
    half4 fragAdd (VertexOutputForwardAddSimple i) : SV_Target { return fragForwardAddSimpleInternal(i); }
#else
    #include "IGSStandardCore.cginc"
    VertexOutputForwardBase vertBase (VertexInput v, half4 color : COLOR) { return vertForwardBase(v, color); }
    VertexOutputForwardAdd vertAdd (VertexInput v, half4 color : COLOR) { return vertForwardAdd(v, color); }

    void fragBase (VertexOutputForwardBase i
		, out half4 resultRT : SV_Target0
		, out half4 colorRT : SV_Target1
		, out half4 specularRT : SV_Target2
		, out half4 normalRT : SV_Target3) 
	{
		resultRT = fragForwardBaseInternal(i, colorRT, specularRT, normalRT);
	}

    half4 fragAdd (VertexOutputForwardAdd i) : SV_Target { return fragForwardAddInternal(i); }
#endif

#endif // UNITY_STANDARD_CORE_FORWARD_INCLUDED
