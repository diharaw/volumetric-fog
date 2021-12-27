#define _USE_MATH_DEFINES
#include <ogl.h>
#include <application.h>
#include <mesh.h>
#include <camera.h>
#include <material.h>
#include <shadow_map.h>
#include <hosek_wilkie_sky_model.h>
#include <memory>
#include <iostream>
#include <stack>
#include <random>
#include <chrono>
#include <random>
#include <fstream>

#define CAMERA_FAR_PLANE 5000.0f

class VolumetricLighting : public dw::Application
{
protected:
    // -----------------------------------------------------------------------------------------------------------------------------------

    bool init(int argc, const char* argv[]) override
    {
        m_shadow_map = std::unique_ptr<dw::ShadowMap>(new dw::ShadowMap(2048));
        m_sky_model  = std::unique_ptr<dw::HosekWilkieSkyModel>(new dw::HosekWilkieSkyModel());

        m_shadow_map->set_extents(2000.0f);
        m_shadow_map->set_near_plane(1.0f);
        m_shadow_map->set_far_plane(4600.0f);
        m_shadow_map->set_backoff_distance(2677.0f);

        m_sun_angle = glm::radians(-60.0f);

        // Create GPU resources.
        if (!create_shaders())
            return false;

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

        render_shadow_map();

        render_main_camera();

        m_sky_model->update(-m_light_direction);
        m_sky_model->render(m_width, m_height, m_main_camera->m_view, m_main_camera->m_projection);

        m_debug_draw.render(nullptr, m_width, m_height, m_main_camera->m_view_projection, m_main_camera->m_position);
    }

    // -----------------------------------------------------------------------------------------------------------------------------------

    void debug_gui()
    {
        ImGui::InputFloat("Bias", &m_bias);
        ImGui::SliderAngle("Sun Angle", &m_sun_angle, 0.0f, -180.0f);
        m_light_direction = glm::normalize(glm::vec3(0.0f, sin(m_sun_angle), cos(m_sun_angle)));
        m_shadow_map->set_direction(m_light_direction);
    }

    // -----------------------------------------------------------------------------------------------------------------------------------

    void window_resized(int width, int height) override
    {
        // Override window resized method to update camera projection.
        m_main_camera->update_projection(60.0f, 1.0f, CAMERA_FAR_PLANE, float(m_width) / float(m_height));
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
        m_mesh_vs = dw::gl::Shader::create_from_file(GL_VERTEX_SHADER, "shader/mesh_vs.glsl");
        m_mesh_fs = dw::gl::Shader::create_from_file(GL_FRAGMENT_SHADER, "shader/mesh_fs.glsl");
        m_shadow_map_fs = dw::gl::Shader::create_from_file(GL_FRAGMENT_SHADER, "shader/shadow_map_fs.glsl");

        if (!m_mesh_vs || !m_mesh_fs || !m_shadow_map_fs)
        {
            DW_LOG_FATAL("Failed to create Shaders");
            return false;
        }

        // Create general shader program
        m_mesh_program = dw::gl::Program::create({ m_mesh_vs, m_mesh_fs });

        if (!m_mesh_program)
        {
            DW_LOG_FATAL("Failed to create Shader Program");
            return false;
        }

        // Create general shader program
        m_shadow_map_program = dw::gl::Program::create({ m_mesh_vs, m_shadow_map_fs });

        if (!m_shadow_map_program)
        {
            DW_LOG_FATAL("Failed to create Shader Program");
            return false;
        }

        return true;
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

        return true;
    }

    // -----------------------------------------------------------------------------------------------------------------------------------

    void create_camera()
    {
        m_main_camera = std::make_unique<dw::Camera>(60.0f, 1.0f, CAMERA_FAR_PLANE, float(m_width) / float(m_height), glm::vec3(0.0f, 3.0f, 15.0f), glm::vec3(-1.0f, 0.0, 0.0f));
        m_main_camera->update();
    }

    // -----------------------------------------------------------------------------------------------------------------------------------

    void render_mesh(dw::Mesh::Ptr mesh, dw::gl::Program::Ptr program, glm::mat4 projection, glm::mat4 view, glm::mat4 model)
    {
        program->set_uniform("u_Projection", projection);
        program->set_uniform("u_View", view);
        program->set_uniform("u_Model", model);
        program->set_uniform("u_LightDirection", m_light_direction);
        program->set_uniform("u_LightViewProj", m_shadow_map->projection() * m_shadow_map->view());
        program->set_uniform("u_Bias", m_bias);

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

            if (program->set_uniform("s_ShadowMap", 1))
                m_shadow_map->texture()->bind(1);

            /*if (m_mesh_program->set_uniform("u_Normal", 1))
                material->normal_texture()->bind(1);

            if (m_mesh_program->set_uniform("u_Metallic", 2))
                material->metallic_texture()->bind(2);

            if (m_mesh_program->set_uniform("u_Roughness", 3))
                material->roughness_texture()->bind(3);*/

            // Issue draw call.
            glDrawElementsBaseVertex(GL_TRIANGLES, submesh.index_count, GL_UNSIGNED_INT, (void*)(sizeof(unsigned int) * submesh.base_index), submesh.base_vertex);
        }
    }

    // -----------------------------------------------------------------------------------------------------------------------------------

    void render_shadow_map()
    {
        m_shadow_map->begin_render();

        m_shadow_map_program->use();

        // Draw scene.
        render_mesh(m_mesh, m_shadow_map_program, m_shadow_map->projection(), m_shadow_map->view(), glm::mat4(1.0f));

        m_shadow_map->end_render();
    }

    // -----------------------------------------------------------------------------------------------------------------------------------

    void render_main_camera()
    {
        glEnable(GL_DEPTH_TEST);
        glDisable(GL_BLEND);
        glEnable(GL_CULL_FACE);
        glCullFace(GL_BACK);

        glBindFramebuffer(GL_FRAMEBUFFER, 0);
        glViewport(0, 0, m_width, m_height);

        glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
        glClearDepth(1.0);
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

        // Bind shader program.
        m_mesh_program->use();

        // Draw scene.
        render_mesh(m_mesh, m_mesh_program, m_main_camera->m_projection, m_main_camera->m_view, glm::mat4(1.0f));
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
    dw::gl::Shader::Ptr                      m_shadow_map_fs;
    dw::gl::Shader::Ptr                      m_mesh_fs;
    dw::gl::Shader::Ptr                      m_mesh_vs;
    dw::gl::Program::Ptr                     m_shadow_map_program;
    dw::gl::Program::Ptr                     m_mesh_program;

    dw::Mesh::Ptr               m_mesh;
    std::unique_ptr<dw::Camera> m_main_camera;

    // Light
    glm::vec3 m_light_direction;
    float     m_sun_angle       = 0.0f;
    float     m_bias      = 0.01f;

    // Camera controls.
    bool  m_mouse_look         = false;
    float m_heading_speed      = 0.0f;
    float m_sideways_speed     = 0.0f;
    float m_camera_sensitivity = 0.05f;
    float m_camera_speed       = 1.0f;
    bool  m_debug_gui          = true;

    // Camera orientation.
    float m_camera_x;
    float m_camera_y;
};

DW_DECLARE_MAIN(VolumetricLighting)