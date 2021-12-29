#include <common.glsl>

// ------------------------------------------------------------------
// DEFINES  ---------------------------------------------------------
// ------------------------------------------------------------------

#define M_PI 3.14159265359
#define EPSILON 0.0001f

// ------------------------------------------------------------------
// OUTPUT VARIABLES  ------------------------------------------------
// ------------------------------------------------------------------

out vec3 FS_OUT_Color;

// ------------------------------------------------------------------
// INPUT VARIABLES  -------------------------------------------------
// ------------------------------------------------------------------

in vec3 FS_IN_WorldPos;
in vec3 FS_IN_Normal;
in vec2 FS_IN_TexCoord;
in vec3 FS_IN_Tangent;
in vec3 FS_IN_Bitangent;

// ------------------------------------------------------------------
// UNIFORMS ---------------------------------------------------------
// ------------------------------------------------------------------

layout(std140, binding = 0) uniform Uniforms
{
    mat4  view;
    mat4  projection;
    mat4  view_proj;
    mat4  light_view_proj;
    mat4  inv_view_proj;
    vec4  light_direction;
    vec4  light_color;
    vec4  camera_position;
    vec4  bias_near_far_pow;
    vec4  aniso_density_scattering_absorption;
    ivec4 width_height;
};

uniform sampler2D s_Albedo;
uniform sampler2D s_Normal;
uniform sampler2D s_Metallic;
uniform sampler2D s_Roughness;
uniform sampler2D s_ShadowMap;
uniform sampler3D s_VoxelGrid;
uniform sampler2D s_BlueNoise;

// ------------------------------------------------------------------
// FUNCTIONS --------------------------------------------------------
// ------------------------------------------------------------------

float sample_shadow_map(vec2 coord, float z)
{
    // get closest depth value from light's perspective (using [0,1] range fragPosLight as coords)
    float closest_depth = texture(s_ShadowMap, coord).r;
    // get depth of current fragment from light's perspective
    float current_depth = z;
    // check whether current frag pos is in shadow
    float bias = bias_near_far_pow.x;
    return current_depth - bias > closest_depth ? 1.0 : 0.0;
}

// ------------------------------------------------------------------

float visibility(vec3 p)
{
    // Transform frag position into Light-space.
    vec4 light_space_pos = light_view_proj * vec4(p, 1.0);

    // Perspective divide
    vec3 proj_coords = light_space_pos.xyz / light_space_pos.w;

    // Transform to [0,1] range
    proj_coords = proj_coords * 0.5 + 0.5;

    if (any(greaterThan(proj_coords.xy, vec2(1.0f))) || any(lessThan(proj_coords.xy, vec2(0.0f))))
        return 1.0f;

    return 1.0 - sample_shadow_map(proj_coords.xy, proj_coords.z);
}

// ------------------------------------------------------------------

vec3 get_normal_from_map(vec3 tangent, vec3 bitangent, vec3 normal, vec2 tex_coord, sampler2D normal_map)
{
    // Create TBN matrix.
    mat3 TBN = mat3(normalize(tangent), normalize(bitangent), normalize(normal));

    // Sample tangent space normal vector from normal map and remap it from [0, 1] to [-1, 1] range.
    vec3 n = texture(normal_map, tex_coord).xyz;

    n.y = 1.0 - n.y;

    n = normalize(n * 2.0 - 1.0);

    // Multiple vector by the TBN matrix to transform the normal from tangent space to world space.
    n = normalize(TBN * n);

    return n;
}

// ------------------------------------------------------------------------

vec3 F_schlick(in vec3 f0, in float vdoth)
{
    return f0 + (vec3(1.0) - f0) * (pow(1.0 - vdoth, 5.0));
}

// ------------------------------------------------------------------------

float D_ggx(in float ndoth, in float alpha)
{
    float a2    = alpha * alpha;
    float denom = (ndoth * ndoth) * (a2 - 1.0) + 1.0;

    return a2 / max(EPSILON, (M_PI * denom * denom));
}

// ------------------------------------------------------------------------

float G1_schlick_ggx(in float roughness, in float ndotv)
{
    float k = ((roughness + 1) * (roughness + 1)) / 8.0;

    return ndotv / max(EPSILON, (ndotv * (1 - k) + k));
}

// ------------------------------------------------------------------------

float G_schlick_ggx(in float ndotl, in float ndotv, in float roughness)
{
    return G1_schlick_ggx(roughness, ndotl) * G1_schlick_ggx(roughness, ndotv);
}

// ------------------------------------------------------------------------

vec3 evaluate_specular_brdf(in float roughness, in vec3 F, in float ndoth, in float ndotl, in float ndotv)
{
    float alpha = roughness * roughness;
    return (D_ggx(ndoth, alpha) * F * G_schlick_ggx(ndotl, ndotv, roughness)) / max(EPSILON, (4.0 * ndotl * ndotv));
}

// ------------------------------------------------------------------------

vec3 evaluate_diffuse_brdf(in vec3 diffuse_color)
{
    return diffuse_color / M_PI;
}

// ------------------------------------------------------------------------

vec3 evaluate_uber_brdf(in vec3 diffuse_color, in float roughness, in vec3 N, in vec3 F0, in vec3 Wo, in vec3 Wh, in vec3 Wi)
{
    float NdotL = max(dot(N, Wi), 0.0);
    float NdotV = max(dot(N, Wo), 0.0);
    float NdotH = max(dot(N, Wh), 0.0);
    float VdotH = max(dot(Wi, Wh), 0.0);

    vec3 F        = F_schlick(F0, VdotH);
    vec3 specular = evaluate_specular_brdf(roughness, F, NdotH, NdotL, NdotV);
    vec3 diffuse  = evaluate_diffuse_brdf(diffuse_color.xyz);

    return (vec3(1.0) - F) * diffuse + specular;
}

// ------------------------------------------------------------------------

vec3 direct_lighting(in vec3 Wo, in vec3 N, in vec3 P, in vec3 F0, in vec3 diffuse_color, in float roughness)
{
    const vec3 Wi = -light_direction.xyz;
    const vec3 Wh = normalize(Wo + Wi);

    vec3 brdf = evaluate_uber_brdf(diffuse_color, roughness, N, F0, Wo, Wh, Wi);

    vec3 Li = light_color.xyz;

    return brdf * Li * visibility(FS_IN_WorldPos);
}

// ------------------------------------------------------------------

vec3 add_inscattered_light(vec3 color, vec3 world_pos)
{
    vec3 uv = world_to_uv(world_pos, bias_near_far_pow.y, bias_near_far_pow.z, bias_near_far_pow.w, view_proj);

    vec4  scattered_light = textureLod(s_VoxelGrid, uv, 0.0f);
    float transmittance   = scattered_light.a;

    return color * transmittance + scattered_light.rgb;
}

// ------------------------------------------------------------------
// MAIN -------------------------------------------------------------
// ------------------------------------------------------------------

void main()
{
    const vec3  diffuse   = texture(s_Albedo, FS_IN_TexCoord).rgb;
    const float metallic  = texture(s_Metallic, FS_IN_TexCoord).r;
    const float roughness = texture(s_Roughness, FS_IN_TexCoord).r;
    const vec3  N         = get_normal_from_map(FS_IN_Tangent, FS_IN_Bitangent, FS_IN_Normal, FS_IN_TexCoord, s_Normal);

    const vec3 Wo = normalize(camera_position.xyz.xyz - FS_IN_WorldPos);
    const vec3 F0 = mix(vec3(0.04f), diffuse, metallic);

    vec3 color = direct_lighting(Wo, N, FS_IN_WorldPos, F0, diffuse, roughness);

    // Ambient
    color += diffuse * 0.2f;

    // Volumetric Light
    color = add_inscattered_light(color, FS_IN_WorldPos);

    // Tone Map
    color = color / (color + vec3(1.0));

    // Gamma Correct
    color = pow(color, vec3(1.0 / 2.2));

    FS_OUT_Color = color;
}

// ------------------------------------------------------------------