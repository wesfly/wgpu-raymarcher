use winit::{
    event::*,
    keyboard::{KeyCode, PhysicalKey},
};

use crate::State;

pub fn handle_input(state: &mut State, event: &WindowEvent) -> bool {
    match event {
        WindowEvent::MouseInput {
            state: button_state,
            button: MouseButton::Left,
            ..
        } => {
            state.mouse_pressed = *button_state == ElementState::Pressed;
            true
        }
        WindowEvent::CursorMoved { position, .. } => {
            if state.mouse_pressed {
                let new_pos = (position.x as f32, position.y as f32);
                let delta = (
                    new_pos.0 - state.mouse_position.0,
                    new_pos.1 - state.mouse_position.1,
                );

                // Update camera rotation
                state.camera_rotation.0 += delta.0 * 0.01;
                state.camera_rotation.1 += delta.1 * -0.01;

                // Clamp pitch to prevent camera flipping
                state.camera_rotation.1 = state
                    .camera_rotation
                    .1
                    .max(-std::f32::consts::PI / 2.0 + 0.1)
                    .min(std::f32::consts::PI / 2.0 - 0.1);
            }
            state.mouse_position = (position.x as f32, position.y as f32);
            true
        }
        WindowEvent::KeyboardInput {
            event:
                KeyEvent {
                    state: ElementState::Pressed,
                    physical_key: PhysicalKey::Code(key),
                    ..
                },
            ..
        } => {
            match key {
                KeyCode::KeyF => {
                    state.fps_cap_enabled = !state.fps_cap_enabled;
                    log::info!(
                        "FPS cap {} (target: {} FPS)",
                        if state.fps_cap_enabled {
                            "enabled"
                        } else {
                            "disabled"
                        },
                        state.target_fps
                    );

                    // Update the window title to show the cap status
                    state.update_window_title();

                    true
                }
                KeyCode::KeyW => {
                    state.cube_position.2 += 0.5;
                    true
                }
                KeyCode::KeyS => {
                    state.cube_position.2 -= 0.5;
                    true
                }
                _ => false,
            }
        }
        _ => false,
    }
}
