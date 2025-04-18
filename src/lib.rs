// Great thanks to https://github.com/sotrh/learn-wgpu
// This code is modified

use std::{
    iter,
    time::{Duration, Instant},
};

use winit::{
    event::*,
    event_loop::EventLoop,
    keyboard::{KeyCode, PhysicalKey},
    window::Window,
};

#[cfg(target_arch = "wasm32")]
use wasm_bindgen::prelude::*;

struct State<'a> {
    surface: wgpu::Surface<'a>,
    device: wgpu::Device,
    queue: wgpu::Queue,
    config: wgpu::SurfaceConfiguration,
    size: winit::dpi::PhysicalSize<u32>,
    render_pipeline: wgpu::RenderPipeline,
    window: &'a Window,
    start_time: std::time::Instant,
    mouse_pressed: bool,
    mouse_position: (f32, f32),
    camera_rotation: (f32, f32), // (yaw, pitch)
    frame_count: u32,
    last_fps_update: std::time::Instant,
    fps: f64,
    fps_cap_enabled: bool,
    target_fps: u32,
    last_frame_time: Instant,
}

impl<'a> State<'a> {
    async fn new(window: &'a Window) -> State<'a> {
        let size = window.inner_size();

        let instance = wgpu::Instance::new(&wgpu::InstanceDescriptor {
            #[cfg(not(target_arch = "wasm32"))]
            backends: wgpu::Backends::PRIMARY,
            #[cfg(target_arch = "wasm32")]
            backends: wgpu::Backends::GL,
            ..Default::default()
        });

        let surface = instance.create_surface(window).unwrap();

        let adapter = instance
            .request_adapter(&wgpu::RequestAdapterOptions {
                power_preference: wgpu::PowerPreference::default(),
                compatible_surface: Some(&surface),
                force_fallback_adapter: false,
            })
            .await
            .unwrap();

        let (device, queue) = adapter
            .request_device(&wgpu::DeviceDescriptor {
                label: None,
                required_features: wgpu::Features::PUSH_CONSTANTS,
                required_limits: if cfg!(target_arch = "wasm32") {
                    wgpu::Limits::downlevel_webgl2_defaults()
                } else {
                    wgpu::Limits {
                        max_push_constant_size: 256,
                        ..Default::default()
                    }
                },
                memory_hints: Default::default(),
                trace: wgpu::Trace::Off,
            })
            .await
            .unwrap();

        let surface_caps = surface.get_capabilities(&adapter);

        let surface_format = surface_caps
            .formats
            .iter()
            .copied()
            .find(|f| f.is_srgb())
            .unwrap_or(surface_caps.formats[0]);

        let config = wgpu::SurfaceConfiguration {
            usage: wgpu::TextureUsages::RENDER_ATTACHMENT,
            format: surface_format,
            width: size.width,
            height: size.height,
            present_mode: surface_caps.present_modes[0],
            alpha_mode: surface_caps.alpha_modes[0],
            view_formats: vec![],
            desired_maximum_frame_latency: 2,
        };

        let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("Shader"),
            source: wgpu::ShaderSource::Wgsl(include_str!("shader.wgsl").into()),
        });

        let render_pipeline_layout =
            device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
                label: Some("Render Pipeline Layout"),
                bind_group_layouts: &[],
                push_constant_ranges: &[wgpu::PushConstantRange {
                    stages: wgpu::ShaderStages::VERTEX | wgpu::ShaderStages::FRAGMENT,
                    range: 0..std::mem::size_of::<[f32; 5]>() as u32,
                }],
            });

        let render_pipeline = device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
            label: Some("Render Pipeline"),
            layout: Some(&render_pipeline_layout),
            vertex: wgpu::VertexState {
                module: &shader,
                entry_point: Some("vs_main"),
                buffers: &[],
                compilation_options: Default::default(),
            },
            fragment: Some(wgpu::FragmentState {
                module: &shader,
                entry_point: Some("fs_main"),
                targets: &[Some(wgpu::ColorTargetState {
                    format: config.format,
                    blend: Some(wgpu::BlendState {
                        color: wgpu::BlendComponent::REPLACE,
                        alpha: wgpu::BlendComponent::REPLACE,
                    }),
                    write_mask: wgpu::ColorWrites::ALL,
                })],
                compilation_options: Default::default(),
            }),
            primitive: wgpu::PrimitiveState {
                topology: wgpu::PrimitiveTopology::TriangleList,
                strip_index_format: None,
                front_face: wgpu::FrontFace::Ccw,
                cull_mode: Some(wgpu::Face::Back),
                polygon_mode: wgpu::PolygonMode::Fill,
                unclipped_depth: false,
                conservative: false,
            },
            depth_stencil: None,
            multisample: wgpu::MultisampleState {
                count: 1,
                mask: !0,
                alpha_to_coverage_enabled: false,
            },
            multiview: None,
            cache: None,
        });

        surface.configure(&device, &config);

        Self {
            surface,
            device,
            queue,
            size,
            config,
            render_pipeline,
            window,
            start_time: std::time::Instant::now(),
            mouse_pressed: false,
            mouse_position: (0.0, 0.0),
            camera_rotation: (0.0, 0.0),
            frame_count: 0,
            last_fps_update: std::time::Instant::now(),
            fps: 0.0,
            fps_cap_enabled: true,
            target_fps: 60,
            last_frame_time: Instant::now(),
        }
    }

    pub fn window(&self) -> &Window {
        &self.window
    }

    pub fn resize(&mut self, new_size: winit::dpi::PhysicalSize<u32>) {
        if new_size.width > 0 && new_size.height > 0 {
            self.size = new_size;
            self.config.width = new_size.width;
            self.config.height = new_size.height;
            self.surface.configure(&self.device, &self.config);
        }
    }

    fn input(&mut self, event: &WindowEvent) -> bool {
        match event {
            WindowEvent::MouseInput {
                state,
                button: MouseButton::Left,
                ..
            } => {
                self.mouse_pressed = *state == ElementState::Pressed;
                true
            }
            WindowEvent::CursorMoved { position, .. } => {
                if self.mouse_pressed {
                    let new_pos = (position.x as f32, position.y as f32);
                    let delta = (
                        new_pos.0 - self.mouse_position.0,
                        new_pos.1 - self.mouse_position.1,
                    );

                    // Update camera rotation
                    self.camera_rotation.0 += delta.0 * 0.01;
                    self.camera_rotation.1 += delta.1 * -0.01;

                    // Clamp pitch to prevent camera flipping
                    self.camera_rotation.1 = self
                        .camera_rotation
                        .1
                        .max(-std::f32::consts::PI / 2.0 + 0.1)
                        .min(std::f32::consts::PI / 2.0 - 0.1);
                }
                self.mouse_position = (position.x as f32, position.y as f32);
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
                    // Toggle FPS cap with the F key
                    KeyCode::KeyF => {
                        self.fps_cap_enabled = !self.fps_cap_enabled;
                        log::info!(
                            "FPS cap {} (target: {} FPS)",
                            if self.fps_cap_enabled {
                                "enabled"
                            } else {
                                "disabled"
                            },
                            self.target_fps
                        );

                        // Update the window title to show the cap status
                        self.update_window_title();

                        true
                    }
                    _ => false,
                }
            }
            _ => false,
        }
    }

    fn update(&mut self) {}

    fn update_window_title(&self) {
        let cap_status = if self.fps_cap_enabled {
            format!("(capped at {} FPS)", self.target_fps)
        } else {
            "(uncapped)".to_string()
        };

        self.window.set_title(&format!(
            "{} - FPS: {:.1} {}",
            env!("CARGO_PKG_NAME"),
            self.fps,
            cap_status
        ));
    }

    fn render(&mut self) -> Result<(), wgpu::SurfaceError> {
        // If FPS cap is enabled, wait until the next frame should be rendered
        if self.fps_cap_enabled {
            let frame_duration = Duration::from_secs_f64(1.0 / self.target_fps as f64);
            let elapsed = self.last_frame_time.elapsed();

            if elapsed < frame_duration {
                // Sleep for the remaining time
                let sleep_duration = frame_duration - elapsed;
                std::thread::sleep(sleep_duration);
            }

            self.last_frame_time = Instant::now();
        }

        let output = self.surface.get_current_texture()?;
        let view = output
            .texture
            .create_view(&wgpu::TextureViewDescriptor::default());

        let mut encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("Render Encoder"),
            });

        {
            let mut render_pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: Some("Render Pass"),
                color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                    view: &view,
                    resolve_target: None,
                    ops: wgpu::Operations {
                        load: wgpu::LoadOp::Clear(wgpu::Color {
                            r: 0.0,
                            g: 0.0,
                            b: 0.0,
                            a: 1.0,
                        }),
                        store: wgpu::StoreOp::Store,
                    },
                })],
                depth_stencil_attachment: None,
                occlusion_query_set: None,
                timestamp_writes: None,
            });

            let elapsed = self.start_time.elapsed().as_secs_f32();

            render_pass.set_pipeline(&self.render_pipeline);
            render_pass.set_push_constants(
                wgpu::ShaderStages::VERTEX | wgpu::ShaderStages::FRAGMENT,
                0,
                bytemuck::cast_slice(&[
                    self.config.height as f32,
                    self.config.height as f32,
                    elapsed,
                    self.camera_rotation.0,
                    self.camera_rotation.1,
                ]),
            );
            render_pass.draw(0..6, 0..1);
        }

        self.queue.submit(iter::once(encoder.finish()));
        output.present();

        // Update FPS counter
        self.frame_count += 1;
        let now = std::time::Instant::now();
        let elapsed = now.duration_since(self.last_fps_update);

        if elapsed.as_secs_f64() > 0.1 {
            self.fps = self.frame_count as f64 / elapsed.as_secs_f64();
            self.frame_count = 0;
            self.last_fps_update = now;

            self.update_window_title();
        }

        Ok(())
    }
}

#[cfg_attr(target_arch = "wasm32", wasm_bindgen(start))]
pub async fn run() {
    cfg_if::cfg_if! {
        if #[cfg(target_arch = "wasm32")] {
            std::panic::set_hook(Box::new(console_error_panic_hook::hook));
            console_log::init_with_level(log::Level::Warn).expect("Could't initialize logger");
        } else {
            env_logger::init();
        }
    }

    let event_loop = EventLoop::new().unwrap();
    let title = env!("CARGO_PKG_NAME");
    let window = winit::window::WindowBuilder::new()
        .with_title(title)
        .build(&event_loop)
        .unwrap();

    #[cfg(target_arch = "wasm32")]
    {
        use winit::dpi::PhysicalSize;
        let _ = window.request_inner_size(PhysicalSize::new(650, 400));

        use winit::platform::web::WindowExtWebSys;
        web_sys::window()
            .and_then(|win| win.document())
            .and_then(|doc| {
                let dst = doc.get_element_by_id("wasm-example")?;
                let canvas = web_sys::Element::from(window.canvas()?);
                dst.append_child(&canvas).ok()?;
                Some(())
            })
            .expect("Couldn't append canvas to document body.");
    }

    let mut state = State::new(&window).await;
    let mut surface_configured = false;

    event_loop
        .run(move |event, control_flow| match event {
            Event::WindowEvent {
                ref event,
                window_id,
            } if window_id == state.window().id() => {
                if !state.input(event) {
                    match event {
                        WindowEvent::CloseRequested
                        | WindowEvent::KeyboardInput {
                            event:
                                KeyEvent {
                                    state: ElementState::Pressed,
                                    physical_key: PhysicalKey::Code(KeyCode::Escape),
                                    ..
                                },
                            ..
                        } => control_flow.exit(),
                        WindowEvent::Resized(physical_size) => {
                            surface_configured = true;
                            state.resize(*physical_size);
                        }
                        WindowEvent::RedrawRequested => {
                            state.window().request_redraw();

                            if !surface_configured {
                                return;
                            }

                            state.update();
                            match state.render() {
                                Ok(_) => {}
                                Err(wgpu::SurfaceError::Lost | wgpu::SurfaceError::Outdated) => {
                                    state.resize(state.size)
                                }
                                Err(
                                    wgpu::SurfaceError::OutOfMemory | wgpu::SurfaceError::Other,
                                ) => {
                                    log::error!("OutOfMemory");
                                    control_flow.exit();
                                }
                                Err(wgpu::SurfaceError::Timeout) => {
                                    log::warn!("Surface timeout")
                                }
                            }
                        }
                        _ => {}
                    }
                }
            }
            _ => {}
        })
        .unwrap();
}
