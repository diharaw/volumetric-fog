// ------------------------------------------------------------------
// OUTPUT VARIABLES  ------------------------------------------------
// ------------------------------------------------------------------

out vec3 FS_OUT_Color;

// ------------------------------------------------------------------
// INPUT VARIABLES  -------------------------------------------------
// ------------------------------------------------------------------

in vec3 FS_IN_WorldPos;
in vec3 FS_IN_Normal;
in vec2 FS_IN_UV;
in vec4 FS_IN_NDCFragPos;

// ------------------------------------------------------------------
// UNIFORMS ---------------------------------------------------------
// ------------------------------------------------------------------

uniform float     u_Bias;
uniform vec3 u_LightDirection;
uniform mat4      u_LightViewProj;
uniform sampler2D s_Albedo;
uniform sampler2D s_ShadowMap;

// ------------------------------------------------------------------
// FUNCTIONS --------------------------------------------------------
// ------------------------------------------------------------------

float shadow_occlussion(vec3 p)
{
    // Transform frag position into Light-space.
    vec4 light_space_pos = u_LightViewProj * vec4(p, 1.0);

    vec3 proj_coords = light_space_pos.xyz / light_space_pos.w;
    // transform to [0,1] range
    proj_coords = proj_coords * 0.5 + 0.5;
    // get closest depth value from light's perspective (using [0,1] range fragPosLight as coords)
    float closest_depth = texture(s_ShadowMap, proj_coords.xy).r;
    // get depth of current fragment from light's perspective
    float current_depth = proj_coords.z;
    // check whether current frag pos is in shadow
    float bias   = u_Bias;
    float shadow = current_depth - bias > closest_depth ? 1.0 : 0.0;

    return 1.0 - shadow;
}

// ------------------------------------------------------------------
// MAIN -------------------------------------------------------------
// ------------------------------------------------------------------

void main()
{
    vec3 albedo = texture(s_Albedo, FS_IN_UV).rgb;
    vec3 N      = normalize(FS_IN_Normal);
    vec3 L      = -u_LightDirection; 

    float shadow = shadow_occlussion(FS_IN_WorldPos);
    vec3 color = albedo * clamp(dot(N, L), 0.0, 1.0) * shadow + albedo * 0.2f;

    color = color / (color + vec3(1.0));
    color = pow(color, vec3(1.0 / 2.2));

    FS_OUT_Color = color;
}

// ------------------------------------------------------------------