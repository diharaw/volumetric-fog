// ------------------------------------------------------------------
// DEFINES ----------------------------------------------------------
// ------------------------------------------------------------------

#define VOXEL_GRID_SIZE_Z 128

// ------------------------------------------------------------------
// INPUTS  ----------------------------------------------------------
// ------------------------------------------------------------------

out vec3 FS_OUT_Color;

// ------------------------------------------------------------------
// OUTPUTS  ---------------------------------------------------------
// ------------------------------------------------------------------

in vec3 FS_IN_WorldPos;

// ------------------------------------------------------------------
// UNIFORMS  --------------------------------------------------------
// ------------------------------------------------------------------

layout(std140, binding = 0) uniform Uniforms
{
    mat4  view;
    mat4  projection;
    mat4  view_proj;
    mat4  prev_view_proj;
    mat4  light_view_proj;
    mat4  inv_view_proj;
    vec4  light_direction;
    vec4  light_color;
    vec4  camera_position;
    vec4  bias_near_far_pow;
    vec4  aniso_density_scattering_absorption;
    ivec4 width_height;
};

uniform samplerCube s_Cubemap;
uniform sampler3D s_VoxelGrid;

// ------------------------------------------------------------------
// FUNCTIONS --------------------------------------------------------
// ------------------------------------------------------------------

vec3 add_inscattered_light(vec3 color)
{
    vec4 scattered_light = textureLod(s_VoxelGrid, vec3(float(gl_FragCoord.x)/(width_height.x - 1), float(gl_FragCoord.y)/(width_height.y - 1), 1.0f), 0.0f);
    float transmittance = scattered_light.a;

    return color * transmittance + scattered_light.rgb;
}

// ------------------------------------------------------------------
// MAIN -------------------------------------------------------------
// ------------------------------------------------------------------

void main()
{
    vec3 env_color = texture(s_Cubemap, FS_IN_WorldPos).rgb;

    // HDR tonemap and gamma correct
    env_color = env_color / (env_color + vec3(1.0));
    env_color = pow(env_color, vec3(1.0 / 2.2));

    FS_OUT_Color = add_inscattered_light(env_color);
}

// ------------------------------------------------------------------