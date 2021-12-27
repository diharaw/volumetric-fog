// ------------------------------------------------------------------
// INPUT VARIABLES --------------------------------------------------
// ------------------------------------------------------------------

layout(location = 0) in vec3 VS_IN_Position;
layout(location = 1) in vec2 VS_IN_UV;
layout(location = 2) in vec3 VS_IN_Normal;
layout(location = 3) in vec3 VS_IN_Tangent;
layout(location = 4) in vec3 VS_IN_Bitangent;

// ------------------------------------------------------------------
// OUTPUT VARIABLES -------------------------------------------------
// ------------------------------------------------------------------

out vec3 FS_IN_WorldPos;
out vec3 FS_IN_Normal;
out vec2 FS_IN_UV;
out vec4 FS_IN_NDCFragPos;

// ------------------------------------------------------------------
// UNIFORMS ---------------------------------------------------------
// ------------------------------------------------------------------

uniform mat4 u_View;
uniform mat4 u_Projection;
uniform mat4 u_Model;

// ------------------------------------------------------------------
// MAIN -------------------------------------------------------------
// ------------------------------------------------------------------

void main()
{
    vec4 world_pos   = u_Model * vec4(VS_IN_Position, 1.0f);
    FS_IN_WorldPos   = world_pos.xyz;
    FS_IN_Normal     = normalize(normalize(mat3(u_Model) * VS_IN_Normal));
    FS_IN_UV         = VS_IN_UV;
    FS_IN_NDCFragPos = u_Projection * u_View * world_pos;

    gl_Position = FS_IN_NDCFragPos;
}

// ------------------------------------------------------------------
