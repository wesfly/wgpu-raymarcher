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

                // Update camera rotation based on mouse movement
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
                    state: key_state,
                    physical_key: PhysicalKey::Code(key),
                    ..
                },
            ..
        } => {
            match (key, key_state) {
                // Key press events
                (KeyCode::KeyF, ElementState::Pressed) => {
                    state.fps_cap_enabled = !state.fps_cap_enabled;
                    log::info!(
                        "FPS cap {} (target: {} FPS)",
                        if state.fps_cap_enabled { "enabled" } else { "disabled" },
                        state.target_fps
                    );
                    state.update_window_title();
                    true
                }
                (KeyCode::KeyW, ElementState::Pressed) => {
                    state.y_input_axis = 1;
                    true
                }
                (KeyCode::KeyS, ElementState::Pressed) => {
                    state.y_input_axis = -1;
                    true
                }
                // W key released - stop moving forward if that was the active direction
                (KeyCode::KeyW, ElementState::Released) => {
                    if state.y_input_axis == 1 {
                        state.y_input_axis = 0;
                    }
                    true
                }
                // S key released - stop moving backward if that was the active direction
                (KeyCode::KeyS, ElementState::Released) => {
                    if state.y_input_axis == -1 {
                        state.y_input_axis = 0;
                    }
                    true
                }
                _ => false,
            }
        }
        _ => false,
    }
}
