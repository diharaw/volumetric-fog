#define _USE_MATH_DEFINES
#include <ogl.h>
#include <application.h>
#include <mesh.h>
#include <camera.h>
#include <material.h>
#include <shadow_map.h>
#include <hosek_wilkie_sky_model.h>
#include <profiler.h>
#include <memory>
#include <iostream>
#include <stack>
#include <random>
#include <chrono>
#include <random>
#include <fstream>

#define CAMERA_NEAR_PLANE 1.0f
#define CAMERA_FAR_PLANE 500.0f
#define VOXEL_GRID_SIZE_X 160
#define VOXEL_GRID_SIZE_Y 90
#define VOXEL_GRID_SIZE_Z 128

struct UBO
{
    glm::mat4  view;
    glm::mat4  projection;
    glm::mat4  view_proj;
    glm::mat4  light_view_proj;
    glm::mat4  inv_view_proj;
    glm::vec4  light_direction;
    glm::vec4  light_color;
    glm::vec4  camera_position;
    glm::vec4  bias_near_far_pow;
    glm::vec4  aniso_density_scattering_absorption;
    glm::ivec4 width_height;
};

class VolumetricLighting : public dw::Application
{
protected:
    // -----------------------------------------------------------------------------------------------------------------------------------

    bool init(int argc, const char* argv[]) override
    {
        m_shadow_map = std::unique_ptr<dw::ShadowMap>(new dw::ShadowMap(2048));
        m_sky_model  = std::unique_ptr<dw::HosekWilkieSkyModel>(new dw::HosekWilkieSkyModel());

        m_shadow_map->set_extents(180.0f);
        m_shadow_map->set_near_plane(1.0f);
        m_shadow_map->set_far_plane(370.0f);
        m_shadow_map->set_backoff_distance(200.0f);

        m_sun_angle = glm::radians(-58.0f);

        // Create GPU resources.
        if (!create_shaders())
            return false;

        // Create volume textures.
        create_textures();

        // Create UBO
        create_uniform_buffer();

        // Load scene.
        if (!load_scene())
            return false;

        // Create camera.
        create_camera();

        return true;
    }

    // -----------------------------------------------------------------------------------------------------------------------------------

    void update(double delta) override
    {
        if (m_debug_gui)
            debug_gui();

        // Update camera.
        update_camera();

        update_uniforms();

        m_sky_model->update(-m_light_direction);

        render_shadow_map();

        voxel_grid_lighting();

        voxel_grid_accumulation();

        render_main_camera();

        render_skybox();
        
        m_debug_draw.render(nullptr, m_width, m_height, m_main_camera->m_view_projection, m_main_camera->m_position);
    }

    // -----------------------------------------------------------------------------------------------------------------------------------

    void debug_gui()
    {
        ImGui::SliderFloat("Anisotropy", &m_anisotropy, 0.0f, 1.0f);
        ImGui::SliderFloat("Density", &m_density, 0.0f, 1.0f);
        ImGui::SliderFloat("Scattering Coefficient", &m_scattering_coefficient, 0.0f, 1.0f);
        ImGui::SliderFloat("Absorption Coefficient", &m_absorption_coefficient, 0.0f, 1.0f);
        ImGui::SliderFloat("Depth Power", &m_depth_power, 1.0f, 10.0f);
        ImGui::SliderAngle("Sun Angle", &m_sun_angle, 0.0f, -180.0f);
        ImGui::InputFloat("Bias", &m_bias);
        ImGui::InputFloat("Light Intensity", &m_light_intensity);
        ImGui::InputFloat("Ambient Light Intensity", &m_ambient_light_intensity);
        ImGui::ColorEdit3("Light Color", &m_light_color.x);

        m_light_direction = glm::normalize(glm::vec3(0.0f, sin(m_sun_angle), cos(m_sun_angle)));
        m_shadow_map->set_direction(m_light_direction);
    }

    // -----------------------------------------------------------------------------------------------------------------------------------

    void window_resized(int width, int height) override
    {
        // Override window resized method to update camera projection.
        m_main_camera->update_projection(60.0f, CAMERA_NEAR_PLANE, CAMERA_FAR_PLANE, float(m_width) / float(m_height));
    }

    // -----------------------------------------------------------------------------------------------------------------------------------

    void key_pressed(int code) override
    {
        // Handle forward movement.
        if (code == GLFW_KEY_W)
            m_heading_speed = m_camera_speed;
        else if (code == GLFW_KEY_S)
            m_heading_speed = -m_camera_speed;

        // Handle sideways movement.
        if (code == GLFW_KEY_A)
            m_sideways_speed = -m_camera_speed;
        else if (code == GLFW_KEY_D)
            m_sideways_speed = m_camera_speed;

        if (code == GLFW_KEY_SPACE)
            m_mouse_look = true;

        if (code == GLFW_KEY_G)
            m_debug_gui = !m_debug_gui;
    }

    // -----------------------------------------------------------------------------------------------------------------------------------

    void key_released(int code) override
    {
        // Handle forward movement.
        if (code == GLFW_KEY_W || code == GLFW_KEY_S)
            m_heading_speed = 0.0f;

        // Handle sideways movement.
        if (code == GLFW_KEY_A || code == GLFW_KEY_D)
            m_sideways_speed = 0.0f;

        if (code == GLFW_KEY_SPACE)
            m_mouse_look = false;
    }

    // -----------------------------------------------------------------------------------------------------------------------------------

    void mouse_pressed(int code) override
    {
        // Enable mouse look.
        if (code == GLFW_MOUSE_BUTTON_RIGHT)
            m_mouse_look = true;
    }

    // -----------------------------------------------------------------------------------------------------------------------------------

    void mouse_released(int code) override
    {
        // Disable mouse look.
        if (code == GLFW_MOUSE_BUTTON_RIGHT)
            m_mouse_look = false;
    }

    // -----------------------------------------------------------------------------------------------------------------------------------

protected:
    // -----------------------------------------------------------------------------------------------------------------------------------

    dw::AppSettings intial_app_settings() override
    {
        dw::AppSettings settings;

        settings.maximized             = false;
        settings.major_ver             = 4;
        settings.width                 = 1920;
        settings.height                = 1080;
        settings.title                 = "Volumetric Lighting";
        settings.enable_debug_callback = false;

        return settings;
    }

    // -----------------------------------------------------------------------------------------------------------------------------------

private:
    // -----------------------------------------------------------------------------------------------------------------------------------

    bool create_shaders()
    {
        // Create general shaders
        m_mesh_vs             = dw::gl::Shader::create_from_file(GL_VERTEX_SHADER, "shader/mesh_vs.glsl");
        m_mesh_fs             = dw::gl::Shader::create_from_file(GL_FRAGMENT_SHADER, "shader/mesh_fs.glsl");
        m_skybox_vs           = dw::gl::Shader::create_from_file(GL_VERTEX_SHADER, "shader/skybox_vs.glsl");
        m_skybox_fs           = dw::gl::Shader::create_from_file(GL_FRAGMENT_SHADER, "shader/skybox_fs.glsl");
        m_shadow_map_vs       = dw::gl::Shader::create_from_file(GL_VERTEX_SHADER, "shader/shadow_map_vs.glsl");
        m_shadow_map_fs       = dw::gl::Shader::create_from_file(GL_FRAGMENT_SHADER, "shader/shadow_map_fs.glsl");
        m_volume_lighting_cs  = dw::gl::Shader::create_from_file(GL_COMPUTE_SHADER, "shader/volume_lighting_cs.glsl");
        m_solve_scattering_cs = dw::gl::Shader::create_from_file(GL_COMPUTE_SHADER, "shader/solve_scattering_cs.glsl");

        if (!m_mesh_vs || !m_mesh_fs || !m_skybox_vs || !m_skybox_fs || !m_shadow_map_vs || !m_shadow_map_fs || !m_volume_lighting_cs || !m_solve_scattering_cs)
        {
            DW_LOG_FATAL("Failed to create Shaders");
            return false;
        }

        // Create mesh shader program
        m_mesh_program = dw::gl::Program::create({ m_mesh_vs, m_mesh_fs });

        if (!m_mesh_program)
        {
            DW_LOG_FATAL("Failed to create Shader Program");
            return false;
        }

        // Create skybox shader program
        m_skybox_program = dw::gl::Program::create({ m_skybox_vs, m_skybox_fs });

        if (!m_skybox_program)
        {
            DW_LOG_FATAL("Failed to create Shader Program");
            return false;
        }

        // Create shadow map shader program
        m_shadow_map_program = dw::gl::Program::create({ m_shadow_map_vs, m_shadow_map_fs });

        if (!m_shadow_map_program)
        {
            DW_LOG_FATAL("Failed to create Shader Program");
            return false;
        }

        // Create volume lighting shader program
        m_volume_lighting_program = dw::gl::Program::create({ m_volume_lighting_cs });

        if (!m_volume_lighting_program)
        {
            DW_LOG_FATAL("Failed to create Shader Program");
            return false;
        }

        // Create solve scattering shader program
        m_solve_scattering_program = dw::gl::Program::create({ m_solve_scattering_cs });

        if (!m_solve_scattering_program)
        {
            DW_LOG_FATAL("Failed to create Shader Program");
            return false;
        }

        return true;
    }

    // -----------------------------------------------------------------------------------------------------------------------------------

    void create_textures()
    {
        m_lighting_volume    = dw::gl::Texture3D::create(VOXEL_GRID_SIZE_X, VOXEL_GRID_SIZE_Y, VOXEL_GRID_SIZE_Z, 1, GL_RGBA16F, GL_RGBA, GL_HALF_FLOAT);
        m_accumulated_volume = dw::gl::Texture3D::create(VOXEL_GRID_SIZE_X, VOXEL_GRID_SIZE_Y, VOXEL_GRID_SIZE_Z, 1, GL_RGBA16F, GL_RGBA, GL_HALF_FLOAT);

        m_lighting_volume->set_min_filter(GL_LINEAR);
        m_lighting_volume->set_mag_filter(GL_LINEAR);
        m_lighting_volume->set_wrapping(GL_CLAMP_TO_EDGE, GL_CLAMP_TO_EDGE, GL_CLAMP_TO_EDGE);

        m_accumulated_volume->set_min_filter(GL_LINEAR);
        m_accumulated_volume->set_mag_filter(GL_LINEAR);
        m_accumulated_volume->set_wrapping(GL_CLAMP_TO_EDGE, GL_CLAMP_TO_EDGE, GL_CLAMP_TO_EDGE);
    }

    // -----------------------------------------------------------------------------------------------------------------------------------

    void create_uniform_buffer()
    {
        m_ubo = dw::gl::Buffer::create(GL_UNIFORM_BUFFER, GL_MAP_WRITE_BIT, sizeof(UBO));
    }

    // -----------------------------------------------------------------------------------------------------------------------------------

    void update_uniforms()
    {
        UBO* ubo = (UBO*)m_ubo->map(GL_WRITE_ONLY);

        ubo->view                                = m_main_camera->m_view;
        ubo->projection                          = m_main_camera->m_projection;
        ubo->view_proj                           = m_main_camera->m_view_projection;
        ubo->light_view_proj                     = m_shadow_map->projection() * m_shadow_map->view();
        ubo->inv_view_proj                       = glm::inverse(m_main_camera->m_view_projection);
        ubo->light_direction                     = glm::vec4(m_light_direction, 0.0f);
        ubo->light_color                         = glm::vec4(m_light_color * m_light_intensity, m_ambient_light_intensity);
        ubo->camera_position                     = glm::vec4(m_main_camera->m_position, 0.0f);
        ubo->bias_near_far_pow                   = glm::vec4(m_bias, CAMERA_NEAR_PLANE, CAMERA_FAR_PLANE, m_depth_power);
        ubo->aniso_density_scattering_absorption = glm::vec4(m_anisotropy, m_density, m_scattering_coefficient, m_absorption_coefficient);
        ubo->width_height                        = glm::ivec4(m_width, m_height, 0, 0);

        m_ubo->unmap();
    }

    // -----------------------------------------------------------------------------------------------------------------------------------

    bool load_scene()
    {
        m_mesh = dw::Mesh::load("mesh/sponza.obj");

        if (!m_mesh)
        {
            DW_LOG_FATAL("Failed to load mesh");
            return false;
        }

        m_transform = glm::scale(glm::mat4(1.0f), glm::vec3(0.1f));

        return true;
    }

    // -----------------------------------------------------------------------------------------------------------------------------------

    void create_camera()
    {
        m_main_camera = std::make_unique<dw::Camera>(60.0f, CAMERA_NEAR_PLANE, CAMERA_FAR_PLANE, float(m_width) / float(m_height), glm::vec3(0.0f, 3.0f, 15.0f), glm::vec3(-1.0f, 0.0, 0.0f));
        m_main_camera->update();
    }

    // -----------------------------------------------------------------------------------------------------------------------------------

    void render_mesh(dw::Mesh::Ptr mesh, dw::gl::Program::Ptr program, glm::mat4 projection, glm::mat4 view, glm::mat4 model)
    {
        program->set_uniform("u_Model", model);

        if (program->set_uniform("s_ShadowMap", 4))
            m_shadow_map->texture()->bind(4);

        if (program->set_uniform("s_VoxelGrid", 5))
            m_accumulated_volume->bind(5);

        // Bind vertex array.
        mesh->mesh_vertex_array()->bind();

        const auto& submeshes = mesh->sub_meshes();
        const auto& materials = mesh->materials();

        for (uint32_t i = 0; i < submeshes.size(); i++)
        {
            const dw::SubMesh&      submesh  = submeshes[i];
            const dw::Material::Ptr material = materials[submesh.mat_idx];

            if (material->albedo_texture() && program->set_uniform("s_Albedo", 0))
                material->albedo_texture()->bind(0);

            if (material->normal_texture() && program->set_uniform("s_Normal", 1))
                material->normal_texture()->bind(1);

            if (material->metallic_texture() && program->set_uniform("s_Metallic", 2))
                material->metallic_texture()->bind(2);

            if (material->roughness_texture() && program->set_uniform("s_Roughness", 3))
                material->roughness_texture()->bind(3);

            // Issue draw call.
            glDrawElementsBaseVertex(GL_TRIANGLES, submesh.index_count, GL_UNSIGNED_INT, (void*)(sizeof(unsigned int) * submesh.base_index), submesh.base_vertex);
        }
    }

    // -----------------------------------------------------------------------------------------------------------------------------------

    void render_skybox()
    {
        DW_SCOPED_SAMPLE("Render Sky Box");

        glEnable(GL_DEPTH_TEST);
        glDepthFunc(GL_LEQUAL);
        glDisable(GL_CULL_FACE);

        m_skybox_program->use();

        m_sky_model->cube_vao()->bind();

        m_ubo->bind_base(0);

        glBindFramebuffer(GL_FRAMEBUFFER, 0);
        glViewport(0, 0, m_width, m_height);

        if (m_skybox_program->set_uniform("s_Cubemap", 0))
            m_sky_model->texture()->bind(0);

        if (m_skybox_program->set_uniform("s_VoxelGrid", 1))
            m_accumulated_volume->bind(1);

        glDrawArrays(GL_TRIANGLES, 0, 36);

        glDepthFunc(GL_LESS);
    }

    // -----------------------------------------------------------------------------------------------------------------------------------

    void render_shadow_map()
    {
        DW_SCOPED_SAMPLE("Render Shadow Map");

        m_shadow_map->begin_render();

        m_ubo->bind_base(0);

        m_shadow_map_program->use();

        // Draw scene.
        render_mesh(m_mesh, m_shadow_map_program, m_shadow_map->projection(), m_shadow_map->view(), m_transform);

        m_shadow_map->end_render();
    }

    // -----------------------------------------------------------------------------------------------------------------------------------

    void render_main_camera()
    {
        DW_SCOPED_SAMPLE("Render Main Camera");

        glEnable(GL_DEPTH_TEST);
        glDisable(GL_BLEND);
        glEnable(GL_CULL_FACE);
        glCullFace(GL_BACK);

        glBindFramebuffer(GL_FRAMEBUFFER, 0);
        glViewport(0, 0, m_width, m_height);

        glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
        glClearDepth(1.0);
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

        m_ubo->bind_base(0);

        // Bind shader program.
        m_mesh_program->use();

        // Draw scene.
        render_mesh(m_mesh, m_mesh_program, m_main_camera->m_projection, m_main_camera->m_view, m_transform);
    }

    // -----------------------------------------------------------------------------------------------------------------------------------

    void voxel_grid_lighting()
    {
        DW_SCOPED_SAMPLE("Voxel Grid Lighting");

        m_ubo->bind_base(0);

        m_volume_lighting_program->use();

        m_lighting_volume->bind_image(0, 0, 0, GL_WRITE_ONLY, m_lighting_volume->internal_format());

        if (m_volume_lighting_program->set_uniform("s_ShadowMap", 0))
            m_shadow_map->texture()->bind(0);

        const uint32_t LOCAL_SIZE_X = 8;
        const uint32_t LOCAL_SIZE_Y = 8;
        const uint32_t LOCAL_SIZE_Z = 1;

        uint32_t size_x = static_cast<uint32_t>(ceil(float(VOXEL_GRID_SIZE_X) / float(LOCAL_SIZE_X)));
        uint32_t size_y = static_cast<uint32_t>(ceil(float(VOXEL_GRID_SIZE_Y) / float(LOCAL_SIZE_Y)));
        uint32_t size_z = static_cast<uint32_t>(ceil(float(VOXEL_GRID_SIZE_Z) / float(LOCAL_SIZE_Z)));

        glDispatchCompute(size_x, size_y, size_z);
    }

    // -----------------------------------------------------------------------------------------------------------------------------------

    void voxel_grid_accumulation()
    {
        DW_SCOPED_SAMPLE("Voxel Grid Accumulation");

        m_solve_scattering_program->use();

        m_accumulated_volume->bind_image(0, 0, 0, GL_WRITE_ONLY, m_accumulated_volume->internal_format());

        if (m_solve_scattering_program->set_uniform("s_VoxelGrid", 0))
            m_lighting_volume->bind(0);

        glDispatchCompute(VOXEL_GRID_SIZE_X, VOXEL_GRID_SIZE_Y, 1);
    }


    // -----------------------------------------------------------------------------------------------------------------------------------

    void update_camera()
    {
        dw::Camera* current = m_main_camera.get();

        float forward_delta = m_heading_speed * m_delta;
        float right_delta   = m_sideways_speed * m_delta;

        current->set_translation_delta(current->m_forward, forward_delta);
        current->set_translation_delta(current->m_right, right_delta);

        m_camera_x = m_mouse_delta_x * m_camera_sensitivity;
        m_camera_y = m_mouse_delta_y * m_camera_sensitivity;

        if (m_mouse_look)
        {
            // Activate Mouse Look
            current->set_rotatation_delta(glm::vec3((float)(m_camera_y),
                                                    (float)(m_camera_x),
                                                    (float)(0.0f)));
        }
        else
        {
            current->set_rotatation_delta(glm::vec3((float)(0),
                                                    (float)(0),
                                                    (float)(0)));
        }

        current->update();
    }

    // -----------------------------------------------------------------------------------------------------------------------------------

private:
    // General GPU resources.
    std::unique_ptr<dw::ShadowMap>           m_shadow_map;
    std::unique_ptr<dw::HosekWilkieSkyModel> m_sky_model;
    dw::gl::Shader::Ptr                      m_shadow_map_vs;
    dw::gl::Shader::Ptr                      m_shadow_map_fs;
    dw::gl::Shader::Ptr                      m_mesh_fs;
    dw::gl::Shader::Ptr                      m_mesh_vs;
    dw::gl::Shader::Ptr                      m_skybox_fs;
    dw::gl::Shader::Ptr                      m_skybox_vs;
    dw::gl::Shader::Ptr                      m_solve_scattering_cs;
    dw::gl::Shader::Ptr                      m_volume_lighting_cs;
    dw::gl::Program::Ptr                     m_shadow_map_program;
    dw::gl::Program::Ptr                     m_mesh_program;
    dw::gl::Program::Ptr                     m_skybox_program;
    dw::gl::Program::Ptr                     m_solve_scattering_program;
    dw::gl::Program::Ptr                     m_volume_lighting_program;
    dw::gl::Texture3D::Ptr                   m_lighting_volume;
    dw::gl::Texture3D::Ptr                   m_accumulated_volume;
    dw::gl::Buffer::Ptr                      m_ubo;

    dw::Mesh::Ptr               m_mesh;
    glm::mat4                   m_transform;
    std::unique_ptr<dw::Camera> m_main_camera;

    // Volumetrics
    float m_anisotropy             = 0.7f;
    float m_density                = 0.13f;
    float m_scattering_coefficient = 0.5f;
    float m_absorption_coefficient = 0.5f;
    float m_depth_power            = 1.0f;

    // Light
    glm::vec3 m_light_direction;
    glm::vec3 m_light_color = glm::vec3(1.0f);
    float     m_light_intensity = 10.0f;
    float     m_ambient_light_intensity = 0.001f;
    float     m_sun_angle   = 0.0f;
    float     m_bias        = 0.001f;

    // Camera controls.
    bool  m_mouse_look         = false;
    float m_heading_speed      = 0.0f;
    float m_sideways_speed     = 0.0f;
    float m_camera_sensitivity = 0.05f;
    float m_camera_speed       = 0.1f;
    bool  m_debug_gui          = true;

    // Camera orientation.
    float m_camera_x;
    float m_camera_y;
};

DW_DECLARE_MAIN(VolumetricLighting)