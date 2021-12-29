// ------------------------------------------------------------------
// INPUTS  ----------------------------------------------------------
// ------------------------------------------------------------------

layout(location = 0) in vec3 VS_IN_Position;

// ------------------------------------------------------------------
// OUTPUTS  ---------------------------------------------------------
// ------------------------------------------------------------------

out vec3 FS_IN_WorldPos;

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

// ------------------------------------------------------------------
// MAIN  ------------------------------------------------------------
// ------------------------------------------------------------------

void main()
{
    FS_IN_WorldPos = VS_IN_Position;

    mat4 rotView = mat4(mat3(view));
    vec4 clipPos = projection * rotView * vec4(VS_IN_Position, 1.0);

    gl_Position = clipPos.xyww;
}

// ------------------------------------------------------------------