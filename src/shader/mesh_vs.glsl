// ------------------------------------------------------------------
// INPUT VARIABLES --------------------------------------------------
// ------------------------------------------------------------------

layout(location = 0) in vec4 VS_IN_Position;
layout(location = 1) in vec4 VS_IN_TexCoord;
layout(location = 2) in vec4 VS_IN_Normal;
layout(location = 3) in vec4 VS_IN_Tangent;
layout(location = 4) in vec4 VS_IN_Bitangent;

// ------------------------------------------------------------------
// OUTPUT VARIABLES -------------------------------------------------
// ------------------------------------------------------------------

out vec3 FS_IN_WorldPos;
out vec3 FS_IN_Normal;
out vec2 FS_IN_TexCoord;
out vec3 FS_IN_Tangent;
out vec3 FS_IN_Bitangent;

// ------------------------------------------------------------------
// UNIFORMS ---------------------------------------------------------
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
    vec4  time;
    ivec4 width_height;
};

uniform mat4 u_Model;

// ------------------------------------------------------------------
// MAIN -------------------------------------------------------------
// ------------------------------------------------------------------

void main()
{
    vec4 world_pos = u_Model * vec4(VS_IN_Position.xyz, 1.0f);
    FS_IN_WorldPos = world_pos.xyz;
    FS_IN_TexCoord = VS_IN_TexCoord.xy;

    mat3 normal_mat = mat3(u_Model);

    FS_IN_Normal    = normalize(normal_mat * VS_IN_Normal.xyz);
    FS_IN_Tangent   = normal_mat * VS_IN_Tangent.xyz;
    FS_IN_Bitangent = normal_mat * VS_IN_Bitangent.xyz;

    gl_Position = view_proj * world_pos;
}

// ------------------------------------------------------------------
