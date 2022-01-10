(
var include_relative = { |relative_path|
	var path = (PathName(thisProcess.nowExecutingPath).pathOnly +/+ relative_path).standardizePath;
	if (File.exists(path)) {
		var result = this.executeFile(path);
		if (result.isNil) { Error("error importing %".format(path)).throw; } { result };
	} {
		Error("include_relative: file % does not exist".format(path.quote)).throw;
	};
};

var r_engine_root_relative = ".." +/+ ".." +/+ "r";

var lib_root_relative = "lib";
var norns_engine_tester = include_relative.value(lib_root_relative +/+ "norns_engine_tester.scd");
var start_script = norns_engine_tester['start_script'];
var script_name = PathName(thisProcess.nowExecutingPath).fileNameWithoutExtension;

start_script.value(script_name) {
	// scriptname: skev
	// v1.3.0 @jah
	var common = include_relative.value("lib/common.scd");
	var common_init_script_state = common[\init_script_state];
	var common_cleanup = common[\cleanup];
	var common_redraw = common[\redraw];
	var common_enc = common[\enc];
	var common_key = common[\key];
	var common_mouse = common[\mouse];
	var common_add_params = common[\add_params];
	var common_render_arc = common[\render_arc];
	var common_get_param_id_for_current_page = common[\get_param_id_for_current_page];
	var common_load_settings_and_params = common[\load_settings_and_params];
	var common_calculate_ui_page_label_widths = common[\calculate_ui_page_label_widths];
	var common_create_and_start_polls = common[\create_and_start_polls];
	var common_update_page_transition = common[\update_page_transition];

	var rrrr = include_relative.value(r_engine_root_relative +/+ "lib" +/+ "r.scd");
	var rrrr_lib = rrrr[\lib];
	var r_specs = rrrr_lib[\specs];

	var formatters = include_relative.value(lib_root_relative +/+ "formatters.scd");
	var custom_formatters = include_relative.value(lib_root_relative +/+ "formatters.scd");

	var capped_list = include_relative.value("lib/capped_list.scd");
	var capped_list_create = capped_list[\create];
	var capped_list_push = capped_list[\push];

	var ui_dirty = false;

	var ui_refresh_rate = 35;

	var settings_file = "skev.data";

	var script_state;

	var pages = [
		[ (id: 'freq_shift'), (id: 'pitch_ratio') ],
		[ (id: 'pitch_dispersion'), ( id: 'time_dispersion') ],
		[ (id: 'lfo_rate'), (id: 'lfo_rate') ],
		[ (id: 'lfo_to_freq_shift'), (id: 'lfo_to_pitch_ratio') ]
	];

	var arc_device;

	var show_event_indicator = false;

	var event_flash_frames = 5;
	var event_flash_frame_counter = nil;

	var flash_event = {
		event_flash_frame_counter = event_flash_frames;
	};
	  
	var update_event_indicator = {
		if (event_flash_frame_counter.notNil) {
			event_flash_frame_counter = event_flash_frame_counter - 1;
			case
			{ event_flash_frame_counter == 0 } {
				event_flash_frame_counter = nil;
				show_event_indicator = false;
				ui_dirty = true;
			}
			{ show_event_indicator.not } {
				show_event_indicator = true;
				ui_dirty = true;
			};
		};
	};

	var refresh_ui = {
		if (script_state[\target_page].notNil) {
			common_update_page_transition.value(script_state);
			ui_dirty = true;
		};

		update_event_indicator.value();

		if (ui_dirty) {
			common_render_arc.value(~params, script_state, pages, arc_device);
			arc_device.refresh_();

			~redraw.value();

			ui_dirty = false;
		};
	};

	var init_ui_refresh_metro = {
		var ui_refresh_metro = ~metro.init_();
		ui_refresh_metro.event = refresh_ui;
		ui_refresh_metro.time = 1/ui_refresh_rate;
		ui_refresh_metro.start_();
	};

	var init_ui = {
		arc_device = ~arc.connect_();

		arc_device[\delta] = { |n, delta| // not .delta notation to suppress self argument?
			var d;
			var id;
			var val;

			flash_event.value();

			if (script_state[\fine]) {
				d = delta/5;
			} {
				d = delta;
			};
			id = common_get_param_id_for_current_page.value(pages, script_state, n-1); // TODO: zero-based
			val = ~params.get_raw_(id);
			~params.set_raw_(id, val+(d/500));
			ui_dirty = true;
		};

		init_ui_refresh_metro.value();
	};

	var init_r_modules = {
		create_modules.value();
		connect_modules.value();
		~engine.pollvisual_(1, "FreqShift=Frequency");
		~engine.pollvisual_(2, "PitchShift=PitchRatio");
	};

	var create_modules = {
		~engine.new_("LFO", "MultiLFO");
		~engine.new_("SoundIn", "SoundIn");
		~engine.new_("PitchShift", "PShift");
		~engine.new_("FreqShift", "FShift");
		~engine.new_("Amplifier", "SGain");
		~engine.new_("SoundOut", "SoundOut");
	};

	var connect_modules = {
		~engine.connect_("LFO/Sine", "FreqShift*FM");
		~engine.connect_("LFO/Sine", "PitchShift*PitchRatioModulation");

		~engine.connect_("SoundIn/Left", "PitchShift*Left");
		~engine.connect_("SoundIn/Right", "PitchShift*Right");
		~engine.connect_("PitchShift/Left", "FreqShift*Left");
		~engine.connect_("PitchShift/Right", "FreqShift*Right");
		~engine.connect_("FreqShift/Left", "Amplifier*Left");
		~engine.connect_("FreqShift/Right", "Amplifier*Right");
		~engine.connect_("Amplifier/Left", "SoundOut*Left");
		~engine.connect_("Amplifier/Right", "SoundOut*Right");
	};

	var create_visual_values_bufs = { |visual_buf_size|
		IdentityDictionary[
			\freq_shift -> capped_list_create.value(visual_buf_size),
			\pitch_ratio -> capped_list_create.value(visual_buf_size)
		];
	};

	var get_poll_specs = { |visual_values|
		[
			get_freq_shift_poll_spec.value(visual_values),
			get_pitch_ratio_poll_spec.value(visual_values)
		];
	};

	var get_freq_shift_poll_spec = { |visual_values|
		IdentityDictionary[
			\id -> "freq_shift",
			\handler -> { |value|
				var visual_value = r_specs[\FShift][\Frequency].unmap(value);
				capped_list_push.value(visual_values[\freq_shift], visual_value);
			}
		]
	};

	var get_pitch_ratio_poll_spec = { |visual_values|
		IdentityDictionary[
			\id -> "pitch_ratio",
			\handler -> { |value|
				var visual_value = r_specs[\PShift][\PitchRatio].unmap(value);
				capped_list_push.value(visual_values[\pitch_ratio], visual_value);
			}
		]
	};

	var get_param_specs = {
		[
			get_freq_shift_param_spec.value(),
			get_pitch_ratio_param_spec.value(),
			get_pitch_dispersion_param_spec.value(),
			get_time_dispersion_param_spec.value(),
			get_lfo_rate_param_spec.value(),
			get_lfo_to_freq_shift_param_spec.value(),
			get_lfo_to_pitch_ratio_param_spec.value(),
			get_main_level_param_spec.value()
		];
	};

	var get_freq_shift_param_spec = {
		IdentityDictionary[
			\type -> "control",
			\id -> "freq_shift",
			\controlspec -> r_specs[\FShift][\Frequency],
			\name -> "Frequency Shift",
			\narrow_name -> "F.SHFT",
			\narrow_formatter -> custom_formatters[\adaptive_freq],
			\action -> { |value|
				~engine.set_("FreqShift.Frequency", value);
			}
		];
	};

	var get_pitch_ratio_param_spec = {
		IdentityDictionary[
			\type -> "control",
			\id -> "pitch_ratio",
			\controlspec -> r_specs[\PShift][\PitchRatio],
			\name -> "Pitch Ratio",
			\formatter -> formatters[\percentage],
			\narrow_name -> "P.RAT",
			\action -> { |value|
				~engine.set_("PitchShift.PitchRatio", value);
			}
		];
	};

	var get_pitch_dispersion_param_spec = {
		IdentityDictionary[
			\type -> "control",
			\id -> "pitch_dispersion",
			\controlspec -> r_specs[\PShift][\PitchDispersion],
			\formatter -> formatters[\percentage],
			\name -> "Pitch Dispersion",
			\narrow_name -> "P.DISP",
			\action -> { |value|
				~engine.set_("PitchShift.PitchDispersion", value);
			}
		];
	};

	var get_time_dispersion_param_spec = {
		IdentityDictionary[
			\type -> "control",
			\id -> "time_dispersion",
			\controlspec -> r_specs[\PShift][\TimeDispersion],
			\formatter -> formatters[\percentage],
			\name -> "Time Dispersion",
			\narrow_name -> "T.DISP",
			\action -> { |value|
				~engine.set_("PitchShift.TimeDispersion", value);
			}
		]
	};

	var get_lfo_rate_param_spec = {
		IdentityDictionary[
			\type -> "control",
			\id -> "lfo_rate",
			\controlspec -> r_specs[\MultiLFO][\Frequency],
			\name -> "LFO Frequency",
			\narrow_name -> "LFO.HZ",
			\narrow_formatter -> custom_formatters[\adaptive_freq],
			\action -> { |value|
				~engine.set_("LFO.Frequency", value);
			}
		]
	};

	var get_lfo_to_freq_shift_param_spec = {
		IdentityDictionary[
			\type -> "control",
			\id -> "lfo_to_freq_shift",
			\controlspec -> r_specs[\FShift][\FM],
			\name -> "LFO to Frequency Shift",
			\formatter -> formatters[\percentage],
			\narrow_name -> ">F.SHIFT",
			\action -> { |value|
				~engine.set_("FreqShift.FM", value);
			}
		]
	};

	var get_lfo_to_pitch_ratio_param_spec = {
		IdentityDictionary[
			\type -> "control",
			\id -> "lfo_to_pitch_ratio",
			\controlspec -> r_specs[\PShift][\PitchRatioModulation],
			\formatter -> formatters[\percentage],
			\name -> "LFO to Pitch Ratio",
			\narrow_name -> ">P.RAT",
			\action -> { |value|
				~engine.set_("PitchShift.PitchRatioModulation", value);
			}
		]
	};

	var get_main_level_param_spec = {
		var spec = r_specs['MGain']['Gain'].copy;
		spec.default = -10;

		IdentityDictionary[
			\id -> "main_level",
			\type -> "control",
			\name -> "Amplifier.Gain",
			\controlspec -> spec,
			\formatter -> formatters.round_(0.1),
			\action -> { |value|
				~engine.set_("Amplifier.Gain", value);
			}
		];
	};

	~engine.name = 'R';

	~init = {
		var visual_buf_size = round(ui_refresh_rate/20);
		var visual_value_bufs;
		var param_specs;
		var poll_specs;
		init_r_modules.value();

		visual_value_bufs = create_visual_values_bufs.value(visual_buf_size);
		param_specs = get_param_specs.value();
		poll_specs = get_poll_specs.value(visual_value_bufs);

		common_add_params.value(~params, param_specs, { ui_dirty = true });

		script_state = common_init_script_state.value(visual_value_bufs);

		common_calculate_ui_page_label_widths.value(~params, ~screen, pages);

		common_load_settings_and_params.value(~params, settings_file);
		common_create_and_start_polls.value(poll_specs, ui_refresh_rate, { ui_dirty = true });

		init_ui.value();
	};

	~cleanup = {
		common_cleanup.value(~params, settings_file);
	};

	~redraw = {
		common_redraw.value(~params, ~screen, pages, script_state, show_event_indicator);
	};

	~enc = { |n, delta|
		common_enc.value(~params, pages, script_state, n, delta);
		ui_dirty = true;
	};

	~key = { |n, z|
		common_key.value(pages, ui_refresh_rate, script_state, n, z);
		ui_dirty = true;
	};

	~mouse = { |... args|
		common_mouse.value(*([~params, ~screen, pages, ui_refresh_rate, script_state]++args));
		ui_dirty = true;
	};
};
)
