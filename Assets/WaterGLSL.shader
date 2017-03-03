Shader "FX/WaterGLSL" {
  Properties {
    _Color0 ("Light color", Color) = (1.0, 1.0, 1.0, 1.0)
    _Color1 ("Mid color", Color) = (1.0, 1.0, 1.0, 1.0)
    _Color2 ("Dark color", Color) = (1.0, 1.0, 1.0, 1.0)
    _Transparency ("Water transparency", Range(0, 1.0)) = 0.75
    _SinSpeed ("Sine speed", Float) = 0.5
    _SinScale ("Sine scale", Float) = 0.3
    _ReflDistort ("Reflection distort", Range(0,1.5)) = 0.44
    _RefrDistort ("Refraction distort", Range(0,1.5)) = 0.40
    _RefrWaveScale ("Refraction wave scale", Range(0.02,0.15)) = 0.063
    _RefrColor ("Refraction color", Color)  = ( .34, .85, .92, 1)
    _SpecColor ("Specular color", Color) = (1.0, 1.0, 1.0, 1.0)
    _Shininess ("Shininess", Float) = 10
    [NoScaleOffset] _Fresnel ("Fresnel (A) ", 2D) = "gray" {}
    [NoScaleOffset] _BumpMap ("Normalmap ", 2D) = "bump" {}
    WaveSpeed ("Wave speed (map1 x,y; map2 x,y)", Vector) = (19,9,-16,-7)
    [NoScaleOffset] _ReflectiveColor ("Reflective color (RGB) fresnel (A) ", 2D) = "" {}
    [HideInInspector] _ReflectionTex ("Internal Reflection", 2D) = "" {}
    [HideInInspector] _RefractionTex ("Internal Refraction", 2D) = "" {}
  }


  // -----------------------------------------------------------
  // Fragment program cards


  Subshader {
    Tags { "WaterMode" = "Refractive" "RenderType" = "Transparent" }
    LOD 100
    Blend One OneMinusSrcAlpha

    Pass {
        GLSLPROGRAM

#include "UnityCG.glslinc"

      uniform vec4 _LightColor0;
      uniform vec4 _SpecColor;
      uniform float _Shininess;

      uniform vec4 _WaveScale4;
      uniform vec4 _WaveOffset;

      uniform float _ReflDistort;
      uniform float _RefrDistort;

#ifdef VERTEX
      uniform vec4 _Color0;
      uniform vec4 _Color1;
      uniform vec4 _Color2;

      uniform float _SinSpeed;
      uniform float _SinScale;

      flat out vec4 color;
      smooth out vec4 reflection;
      smooth out vec4 view_dir;
      smooth out vec2 bumpuv0;
      smooth out vec2 bumpuv1;

      vec4 ComputeScreenPos(vec4 pos)
      {
        vec4 o = pos * 0.5;
        o.xy = vec2(o.x, o.y*_ProjectionParams.x) + o.w;
        o.zw = pos.zw;
        return o;
      }

      // TODO: Support multiple lights
      vec4 specular()
      {
        vec4 base_color = _Color0;
        if(gl_Vertex.y < 0.5)
        { base_color = _Color2; }
        else if(gl_Vertex.y < 0.75)
        { base_color = _Color1; }

        vec3 normalDirection = normalize(vec3(vec4(gl_Normal, 0.0) * unity_WorldToObject));
        vec3 viewDirection = normalize(vec3(vec4(_WorldSpaceCameraPos, 1.0) - unity_ObjectToWorld * gl_Vertex));
        vec3 lightDirection;
        float attenuation = 1.0;

        if(0.0 == _WorldSpaceLightPos0.w) /* Directional light? */
        {
          /* no attenuation. */
          lightDirection = normalize(vec3(_WorldSpaceLightPos0));
        }
        else /* Point or spot light. */
        {
          vec3 vertexToLightSource = vec3(_WorldSpaceLightPos0 - unity_ObjectToWorld * gl_Vertex);
          float distance = length(vertexToLightSource);
          attenuation = 1.0 / distance; /* Linear attenuation. */
          lightDirection = normalize(vertexToLightSource);
        }

        vec3 ambientLighting = vec3(gl_LightModel.ambient) * vec3(base_color);
        float sharpness = max(0.0, dot(normalDirection, lightDirection));
        vec3 diffuseReflection = attenuation * vec3(_LightColor0) * vec3(base_color) * sharpness;

        vec3 specularReflection;
        if(dot(normalDirection, lightDirection) < 0.0) /* Light source on the wrong side? */
        {
          /* No specular reflection. */
          specularReflection = vec3(0.0, 0.0, 0.0);
        }
        else /* Light source on the right side. */
        {
          specularReflection = attenuation * vec3(_LightColor0)
            * vec3(_SpecColor) * pow(max(0.0, dot(
                    reflect(-lightDirection, normalDirection),
                    viewDirection)), _Shininess);
        }

        return vec4(ambientLighting + diffuseReflection + specularReflection, 1.0);
      }

      void main()
      {
        vec4 vertex = gl_Vertex;
        vertex.y = sin(_Time.w * _SinSpeed + vertex.x + vertex.y + vertex.z) * _SinScale;
        gl_Position = gl_ModelViewProjectionMatrix * vertex;

        color = specular();
        reflection = ComputeScreenPos(gl_Position) + (vertex.y * _ReflDistort);

        /* Scroll bump waves. */
        vec4 wpos = unity_ObjectToWorld * vertex;
        vec4 temp = wpos.xzxz * _WaveScale4 + _WaveOffset;
        bumpuv0 = temp.xy;
        bumpuv1 = temp.wz;

        /* Object space view direction (will normalize per pixel). */
        view_dir.xzy = WorldSpaceViewDir(vertex);
      }
#endif

#ifdef FRAGMENT
      uniform float _Transparency;
      uniform sampler2D _ReflectionTex;
      uniform sampler2D _ReflectiveColor;
      uniform sampler2D _Fresnel;
      uniform sampler2D _RefractionTex;
      uniform vec4 _RefrColor;
      uniform sampler2D _BumpMap;

      flat in vec4 color;
      smooth in vec4 reflection;
      smooth in vec4 view_dir;
      smooth in vec2 bumpuv0;
      smooth in vec2 bumpuv1;

      vec3 UnpackNormal(vec4 norm)
      { return (vec3(norm) - 0.5) * 2.0; }

      void main()
      {
        vec4 view_dir_norm = normalize(view_dir);

        /* Combine two scrolling bumpmaps into one. */
        vec3 bump1 = UnpackNormal(texture2D(_BumpMap, bumpuv0)).rgb;
        vec3 bump2 = UnpackNormal(texture2D(_BumpMap, bumpuv1)).rgb;
        vec3 bump = (bump1 + bump2) * 0.5;

        /* Fresnel factor. */
        float fres = dot(vec3(view_dir_norm), bump);

        /* Perturb reflection/refraction UVs by bumpmap, and lookup colors. */
        vec4 uv1 = reflection; uv1.xy += vec2(bump) * _ReflDistort;
        vec4 refl = texture2DProj(_ReflectionTex, uv1);
        vec4 uv2 = reflection; uv2.xy -= vec2(bump) * _RefrDistort;
        vec4 refr = texture2DProj(_RefractionTex, uv2) * _RefrColor;

        /* Final color is between refracted and reflected, based on fresnel. */
        float fresnel = texture2D(_Fresnel, vec2(fres, fres)).a;
        gl_FragColor = mix(refr, refl, fresnel) * color;
        gl_FragColor.a = _Transparency;
      }
#endif
      ENDGLSL
    }
  }
}
