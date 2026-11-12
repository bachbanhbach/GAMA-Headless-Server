/**
 * Name: TwoLayerFarm
 * Description: OOP pig farm simulation with config-driven grid layout.
 *
 * Key features:
 *   - Pre-simulation parameter panel: NUM_PENS, PENS_PER_ROW, disease config
 *   - "Set Configuration" button to apply changes without restarting
 *   - Grid layout: pens arranged in rows (max PENS_PER_ROW per row)
 *   - Cross-pen wall transmission within same row only
 *   - Immunity: recovered pigs cannot be re-infected
 *   - FarmPig (parent: DiseasePig): unified pig species for all pens
 *   - PenTrough (parent: Trough): unified trough species
 *   - PigPen: macro agent with background image + stats
 *
 * Disease mechanics:
 *   Food disease: FoodDiseaseFactor at troughs -> E->S (mild, recoverable)
 *   Wall transmission: cross-pen reflex -> E->I->R/D (standard SEIR)
 *   Immunity: after recovery (recover_count > 0), pig is immune for life
 *
 * Display architecture:
 *   Layer 1 (Farm Overview): Grid of PigPens, clean macro view
 *   Layer 2 (Pig Pen Detail): Zoomed single pen with grid overlay
 */

model TwoLayerFarm


// =====================================================================
//                              IMPORTS
// =====================================================================
import './food-disease-pig.gaml'


// =====================================================================
//                          GLOBAL AGENT
// =====================================================================
global {
	// ==================== FARM LAYOUT CONSTANTS ====================
	float PEN_WIDTH <- 100.0;
	float PEN_HEIGHT <- 100.0;
	float PEN_GAP <- 2.0;
	float MARGIN_X <- 15.0;
	float MARGIN_Y <- 15.0;
	float ROW_GAP <- 45.0;       // Vertical gap between pen rows (for stats text)

	// ==================== IMAGE ASSETS (CACHED) ====================
	file pen_bg_img <- image_file("../includes/images/background.png");
	file pig_img <- image_file("../includes/images/pig.png");
	file pig_yellow_img <- image_file("../includes/images/pig_yellow.png");
	file pig_red_img <- image_file("../includes/images/pig_red.png");
	file pig_green_img <- image_file("../includes/images/pig_green.png");
	file farmer_img <- image_file("../includes/images/farmer.png");

	// ==================== USER CONFIGURATION ====================
	// Set via experiment parameters before simulation starts.
	int NUM_PENS <- 5;
	int PENS_PER_ROW <- 5;
	int initial_infected_pen <- 1;       // Pen that starts with disease (1-indexed)

	// ==================== DYNAMIC LAYOUT ====================
	int num_cols <- 1;
	int num_rows <- 1;
	list<string> PEN_TYPES <- [];
	list<int> PEN_FOOD_DISEASE_DAYS <- [];
	list<point> PEN_ORIGINS <- [];
	float ENV_WIDTH <- 600.0;
	float ENV_HEIGHT <- 200.0;
	geometry shape <- rectangle(600, 200);

	// ==================== WALL TRANSMISSION ====================
	float WALL_PROXIMITY <- 5.0;

	// ==================== SELECTION STATE ====================
	agent selected_pen <- nil;

	// ==================== CAMERA SETTINGS ====================
	// Overview camera (shows all pens up to 50 pens)
	float overview_cam_x <- 300.0;
	float overview_cam_y <- 200.0;
	float overview_cam_z <- 600.0;
	bool overview_cam_dynamic <- false;

	// Detail view camera (zooms to selected pen, then unlocks for manual mouse zoom)
	float detail_cam_x <- 300.0;
	float detail_cam_y <- 100.0;
	float detail_cam_z <- 130.0;
	bool detail_cam_dynamic <- false;

	// ==================== FARM INITIALIZED FLAG ====================
	bool farm_initialized <- false;


	// ==================== INITIALIZATION ====================
	init {
		// Do NOT auto-initialize. Wait for user to click "Set Configuration".
		// Just set a reasonable environment so the displays can render.
		ENV_WIDTH <- 600.0;
		ENV_HEIGHT <- 400.0;
		shape <- rectangle(ENV_WIDTH, ENV_HEIGHT);
		overview_cam_x <- ENV_WIDTH / 2.0;
		overview_cam_y <- ENV_HEIGHT / 2.0;
		overview_cam_z <- max(ENV_WIDTH * 1.7, ENV_HEIGHT * 1.5);
		overview_cam_dynamic <- true;
		detail_cam_x <- ENV_WIDTH / 2.0;
		detail_cam_y <- ENV_HEIGHT / 2.0;
		detail_cam_z <- 130.0;
		detail_cam_dynamic <- true;
	}


	// ==================== SET CONFIGURATION ACTION ====================
	/**
	 * Called by the "Set Configuration" user_command.
	 * Destroys all existing agents and re-creates the farm with current parameters.
	 */
	action setup_farm {
		// --- Destroy existing agents ---
		ask FarmPig { do die; }
		ask PenTrough { do die; }
		ask PigPen { do die; }
		ask FoodDiseaseFactor { do die; }
		ask Farmer { do die; }
		selected_pen <- nil;

		// --- Grid dimensions ---
		num_cols <- min(NUM_PENS, PENS_PER_ROW);
		num_rows <- int(ceil(NUM_PENS / PENS_PER_ROW));

		// --- Environment size ---
		ENV_WIDTH <- MARGIN_X * 2.0 + num_cols * PEN_WIDTH + (num_cols - 1) * PEN_GAP;
		ENV_HEIGHT <- MARGIN_Y + num_rows * PEN_HEIGHT + (num_rows - 1) * ROW_GAP + 40.0;
		shape <- rectangle(ENV_WIDTH, ENV_HEIGHT);

		// --- Initialize config lists ---
		PEN_TYPES <- list_with(NUM_PENS, "Normal");
		PEN_FOOD_DISEASE_DAYS <- list_with(NUM_PENS, -1);
		PEN_ORIGINS <- [];

		// --- Disease assignment (Only 1 initial infected pen as vector origin) ---
		int initial_idx <- initial_infected_pen - 1;
		if (initial_idx >= 0 and initial_idx < NUM_PENS) {
			PEN_TYPES[initial_idx] <- "Food Disease";
			PEN_FOOD_DISEASE_DAYS[initial_idx] <- 0;
		}

		// --- Calculate pen origins (grid layout) ---
		loop i from: 0 to: NUM_PENS - 1 {
			int row <- int(i / PENS_PER_ROW);
			int col <- i mod PENS_PER_ROW;
			float ox <- MARGIN_X + col * (PEN_WIDTH + PEN_GAP);
			float oy <- MARGIN_Y + row * (PEN_HEIGHT + ROW_GAP);
			PEN_ORIGINS <- PEN_ORIGINS + [{ox, oy}];
		}

		// --- Create PigPen macro agents ---
		loop i from: 0 to: NUM_PENS - 1 {
			create PigPen number: 1 {
				pen_id <- i + 1;
				pen_origin <- PEN_ORIGINS[i];
				location <- pen_origin + {PEN_WIDTH / 2.0, PEN_HEIGHT / 2.0};
				pen_type <- PEN_TYPES[i];
				food_disease_day <- PEN_FOOD_DISEASE_DAYS[i];
			}
		}

		// --- Create pigs and troughs for each pen ---
		loop i from: 0 to: NUM_PENS - 1 {
			point origin <- PEN_ORIGINS[i];
			bool has_food_disease <- (PEN_FOOD_DISEASE_DAYS[i] >= 0);
			PigPen this_pen <- PigPen[i];

			// 20 pigs per pen
			loop j from: 0 to: 19 {
				create FarmPig number: 1 returns: new_pig {
					id <- i * 20 + j;
					pen_id <- i + 1;
					pen_offset <- origin;
					food_disease_mode <- has_food_disease;
					location <- get_relax_loc();

					// SEIR parameters for disease transmission
					max_expose_time <- 15 * 24 * 60;
					avg_expose_time <- 10 * 24 * 60;
					max_infect_time <- 5 * 24 * 60;
					avg_infect_time <- 4 * 24 * 60;
					max_shed_time <- 365 * 24 * 60;
					avg_shed_time <- 365 * 24 * 60;
					u <- 0.4;
					k1 <- 0.42;
					k2 <- 1.59;

					if (has_food_disease) {
						init_weight <- rnd(47.5, 52.5) with_precision 2;
						weight <- init_weight;
					}
				}
				this_pen.my_pigs <- this_pen.my_pigs + new_pig;
			}

			// 5 troughs per pen — positions match background.png
			loop j from: 0 to: 4 {
				create PenTrough number: 1 {
					pen_id <- i + 1;
					location <- origin + trough_locs[j];
				}
			}
		}

		// --- Create Caretaker / Farmer agent ---
		create Farmer number: 1 {
			current_pen_idx <- 0;
			moving_forward <- true;
			state <- "moving";
			has_pathogen <- false;
			location <- PEN_ORIGINS[0] + {68.0, 15.0};
			target_loc <- location;
		}

		// --- Overview camera: fit all pens (up to 50 pens) ---
		overview_cam_x <- ENV_WIDTH / 2.0;
		overview_cam_y <- ENV_HEIGHT / 2.0;
		overview_cam_z <- max(ENV_WIDTH * 1.7, ENV_HEIGHT * 1.5);
		overview_cam_dynamic <- true;

		// --- Detail camera position ---
		detail_cam_x <- ENV_WIDTH / 2.0;
		detail_cam_y <- ENV_HEIGHT / 2.0;
		detail_cam_z <- 130.0;
		detail_cam_dynamic <- true;

		farm_initialized <- true;
	}


	// ==================== CAMERA UPDATE ====================
	// Resets dynamic flags so cameras unlock for manual mouse zoom & pan
	reflex reset_camera_dynamic when: farm_initialized {
		if (overview_cam_dynamic) {
			overview_cam_dynamic <- false;
		}
		if (detail_cam_dynamic) {
			detail_cam_dynamic <- false;
		}
	}

	// Stop after 55 simulated days
	reflex stop_simulation when: farm_initialized and cycle = 60 * 24 * 55 {
		do pause;
	}


	// ==================== CROSS-PEN TRANSMISSION ====================
	// Only between adjacent pens IN THE SAME ROW.
	// Two-directional: left->right AND right->left.
	// Immune pigs (recover_count > 0) are NOT susceptible.
	reflex cross_pen_transmission when: farm_initialized {
		float b <- rnd(0.402, 1.85);
		int pen_count <- length(PEN_ORIGINS);

		loop i from: 0 to: pen_count - 2 {
			int row_i <- int(i / PENS_PER_ROW);
			int row_next <- int((i + 1) / PENS_PER_ROW);

			// Skip if pens are in different rows (no shared wall)
			if (row_i != row_next) {
				// no-op: different rows
			} else {
				int left_id <- i + 1;
				int right_id <- i + 2;

				float left_right_wall <- PEN_ORIGINS[i].x + PEN_WIDTH;
				float right_left_wall <- PEN_ORIGINS[i + 1].x;

				PigPen pen_left <- PigPen[i];
				PigPen pen_right <- PigPen[i + 1];

				// --- Check left pen for sick pigs near right wall ---
				bool left_sick <- false;
				loop pig over: pen_left.my_pigs {
					if ((pig.seir = 1 or pig.seir = 2)
						and pig.location.x >= left_right_wall - WALL_PROXIMITY) {
						left_sick <- true;
						break;
					}
				}

				// --- Check right pen for sick pigs near left wall ---
				bool right_sick <- false;
				loop pig over: pen_right.my_pigs {
					if ((pig.seir = 1 or pig.seir = 2)
						and pig.location.x <= right_left_wall + WALL_PROXIMITY) {
						right_sick <- true;
						break;
					}
				}

				// --- Left -> Right transmission ---
				// Only infect pigs that are susceptible (seir=0) AND have NOT recovered before
				if (left_sick) {
					loop pig over: pen_right.my_pigs {
						if (pig.seir = 0 and pig.recover_count = 0
							and pig.location.x <= right_left_wall + WALL_PROXIMITY
							and flip(1 - e ^ -b)) {
							pig.seir <- 1;
							pig.infection_source <- "wall";
							pig.expose_count_per_day <- pig.expose_count_per_day + 1;
						}
					}
				}

				// --- Right -> Left transmission ---
				if (right_sick) {
					loop pig over: pen_left.my_pigs {
						if (pig.seir = 0 and pig.recover_count = 0
							and pig.location.x >= left_right_wall - WALL_PROXIMITY
							and flip(1 - e ^ -b)) {
							pig.seir <- 1;
							pig.infection_source <- "wall";
							pig.expose_count_per_day <- pig.expose_count_per_day + 1;
						}
					}
				}
			}
		}
	}
}


// =====================================================================
//                     PIGPEN SPECIES (MACRO AGENT)
// =====================================================================
/**
 * PigPen - Represents one pig pen on the farm.
 * Renders background image, manages food disease, tracks stats.
 * Stats are displayed BELOW the pen in the macro view.
 * All pens use background.png (non-flipped) only.
 */
species PigPen {
	int pen_id;
	point pen_origin;
	string pen_type;
	int food_disease_day <- -1;
	list<FarmPig> my_pigs <- [];

	// Aggregated statistics
	float total_weight <- 0.0;
	int pig_count <- 0;
	int exposed_count <- 0;
	int infected_count <- 0;
	int recovered_count <- 0;

	reflex update_stats {
		total_weight <- my_pigs sum_of (each.weight);
		pig_count <- length(my_pigs);
		exposed_count <- my_pigs count (each.seir = 1);
		infected_count <- my_pigs count (each.seir = 2);
		recovered_count <- my_pigs count (each.seir = 3);
	}

	/**
	 * Trigger food disease at the configured day.
	 */
	reflex trigger_food_disease when: food_disease_day >= 0
			and cycle mod (24 * 60) = 0
			and int(cycle / (60 * 24)) = food_disease_day {
		point my_origin <- pen_origin;
		loop j from: 0 to: 4 {
			point t_loc <- my_origin + trough_locs[j];
			create FoodDiseaseFactor number: 1 {
				duration <- 7 * 24 * 60;
				size <- 2.0;
				location <- t_loc;
			}
		}
		food_disease_day <- -1;
	}

	/**
	 * Macro aspect: background image + selection border + compact stats below.
	 * All pens use background.png (non-flipped).
	 */
	aspect macro {
		// --- Background image (cached) ---
		draw pen_bg_img size: {PEN_WIDTH, PEN_HEIGHT};

		// --- Selection highlight (golden border) ---
		if (self = selected_pen) {
			draw rectangle(PEN_WIDTH + 4.0, PEN_HEIGHT + 4.0)
				 color: rgb(0, 0, 0, 0) border: rgb(255, 200, 50) width: 3;
		}

		// --- Pen label ---
		rgb label_color <- pen_type = "Food Disease" ? rgb(255, 170, 80) : rgb(230, 235, 220);
		draw "Pen " + pen_id
			 at: {location.x, pen_origin.y + PEN_HEIGHT + 7.0}
			 color: label_color font: font("Arial", 10, #bold) anchor: #center;

		// --- Type tag ---
		rgb type_color <- pen_type = "Food Disease" ? rgb(255, 140, 60) : rgb(150, 165, 140);
		draw "[" + pen_type + "]"
			 at: {location.x, pen_origin.y + PEN_HEIGHT + 17.0}
			 color: type_color font: font("Arial", 8, #plain) anchor: #center;

		// --- Disease stats (colored by severity) ---
		rgb stat_color <- (exposed_count + infected_count > 0) ? rgb(255, 130, 80) : rgb(130, 145, 120);
		draw "E:" + exposed_count + " I:" + infected_count + " R:" + recovered_count
			 at: {location.x, pen_origin.y + PEN_HEIGHT + 27.0}
			 color: stat_color font: font("Arial", 8, #plain) anchor: #center;
	}
}


// =====================================================================
//                     FARMPIG SPECIES (UNIFIED PIG)
// =====================================================================
/**
 * FarmPig - Unified pig species for all pens.
 * Parent: DiseasePig (SEIR state machine)
 *
 * Immunity: After recovery (recover_count > 0), pig cannot be re-infected.
 *
 * Aspects:
 *   macro  - Farm Overview: pig sprites only, NO ID text (clean)
 *   detail - Pig Pen Detail: pig sprites + small ID, filtered by selected pen
 */
species FarmPig parent: DiseasePig {
	int pen_id;
	point pen_offset <- {0, 0};
	bool food_disease_mode <- false;
	string infection_source <- "none";

	int food_max_expose_time <- 24 * 60;
	int food_avg_expose_time <- 12 * 60;


	// ==================== LOCATION OVERRIDES ====================
	// All pens use non-flipped background, so locations are standard.

	point get_relax_loc {
		return pen_offset + {rnd(60.0, 95.0), rnd(60.0, 95.0)};
	}

	point get_gate_in_loc {
		return pen_offset + {rnd(40.0, 48.0), rnd(48.0, 56.0)};
	}

	point get_gate_out_loc {
		return pen_offset + {95.0, 48.0};
	}

	point get_drink_loc {
		return pen_offset + water_locs[rnd(length(water_locs) - 1)];
	}

	point get_excrete_loc {
		return pen_offset + {rnd(10.0, 40.0), rnd(60.0, 95.0)};
	}


	// ==================== TROUGH INTERACTION ====================

	action eat {
		ask PenTrough where (each.pen_id = self.pen_id) {
			if (add_pig(myself)) {
				myself.location <- location;
				myself.current <- 3;
				myself.duration <- myself.eat_time();
				myself.eat_count <- myself.eat_count + 1;
				break;
			}
		}
	}

	action go_out {
		ask PenTrough where (each.pen_id = self.pen_id) {
			do remove_pig(myself);
		}
		location <- get_gate_out_loc();
		current <- 4;
	}


	// ==================== DISEASE BEHAVIOR OVERRIDES ====================

	/**
	 * Expose action: food disease transmission at troughs.
	 * Immune pigs (recover_count > 0) CANNOT be exposed again.
	 */
	action expose {
		// Immunity check: if this pig has recovered before, it's immune
		if (recover_count > 0) {
			// Pig is immune — skip exposure
		} else if (food_disease_mode and current = 3) {
			ask FoodDiseaseFactor {
				if (expose(myself)) {
					myself.seir <- 1;
					myself.infection_source <- "food";
					myself.expose_count_per_day <- myself.expose_count_per_day + 1;
				}
			}
		}
	}

	action infect {
		if (infection_source = "food") {
			if (is_start_of_day() and (food_max_expose_time <= expose_time
				or flip(1 - e ^ -((expose_time / (24.0 * 60.0)) / (food_avg_expose_time / (24.0 * 60.0)))))) {
				seir <- 0;
				expose_time <- 0;
				recover_count <- recover_count + 1;
				infection_source <- "none";
			} else {
				expose_time <- expose_time + 1;
			}
		} else {
			if (is_start_of_day() and (max_expose_time <= expose_time
				or flip(1 - e ^ -(expose_time / avg_expose_time)))) {
				seir <- 2;
				expose_time <- 0;
			} else {
				expose_time <- expose_time + 1;
			}
		}
	}


	// ==================== FOOD DISEASE BEHAVIOR MODIFIERS ====================

	bool is_hungry {
		if (food_disease_mode and expose_count_per_day > 0) {
			return flip(0.5) and super.is_hungry();
		}
		return super.is_hungry();
	}

	int get_excrete_per_day {
		if (food_disease_mode and expose_count_per_day > 0) {
			return rnd(4, 6);
		}
		return super.get_excrete_per_day();
	}


	// ==================== ASPECTS ====================

	/**
	 * Macro aspect (Farm Overview): pig image only, NO text.
	 * Keeps the overview clean when many pens are visible.
	 */
	aspect macro {
		if(seir = 0) { draw pig_img size: 5.0; }
		else if(seir = 1) { draw pig_yellow_img size: 5.0; }
		else if(seir = 2) { draw pig_red_img size: 5.0; }
		else if(seir = 3) { draw pig_green_img size: 5.0; }
	}

	/**
	 * Detail aspect (Pig Pen Detail): pig image + small ID text.
	 * Only renders pigs belonging to the currently selected pen.
	 */
	aspect detail {
		if (selected_pen != nil and pen_id = PigPen(selected_pen).pen_id) {
			if(seir = 0) {
				draw pig_img size: 5.0;
			}
			else if(seir = 1) {
				draw pig_yellow_img size: 5.0;
			}
			else if(seir = 2) {
				draw pig_red_img size: 5.0;
			}
			else if(seir = 3) {
				draw pig_green_img size: 5.0;
			}

			// Small ID text in the exact center of the pig (plain font, size 3)
			rgb id_color <- (seir = 2) ? rgb(255, 255, 255) : rgb(20, 20, 20);
			draw string(id) at: location color: id_color font: font("Arial", 3, #plain) anchor: #center;
		}
	}
}


// =====================================================================
//                     FARMER SPECIES (CARETAKER AGENT)
// =====================================================================
/**
 * Farmer - The caretaker who feeds the pigs and serves as the disease transmission vector.
 * 
 * Behaviors:
 *   - Patrols pens in order: row by row from top to bottom (0 -> NUM_PENS - 1), then returns (NUM_PENS - 1 -> 0).
 *   - Stops at each pen at the feeding station (near troughs) for FEED_DURATION cycles.
 *   - If the visited pen has sick pigs (exposed or infected), the farmer can get contaminated (carrying pathogen).
 *   - If the farmer is contaminated and visits a healthy pen, the farmer can transmit the disease to that pen.
 *   - Visualization: farmer sprite with green aura (clean) or red pulsing aura (carrier/contaminated).
 */
species Farmer {
	int current_pen_idx <- 0;
	bool moving_forward <- true;
	string state <- "moving";           // "moving" or "feeding"
	int feed_timer <- 0;
	int FEED_DURATION <- 15;            // cycles to feed at each pen
	float move_speed <- 2.0;
	bool has_pathogen <- false;         // True if carrying pathogen from an infected pen
	point target_loc <- {0, 0};

	reflex patrol when: farm_initialized and length(PEN_ORIGINS) > 0 {
		if (state = "moving") {
			target_loc <- PEN_ORIGINS[current_pen_idx] + {68.0, 15.0};
			float dist <- distance_to(location, target_loc);
			if (dist <= move_speed or dist = 0.0) {
				location <- target_loc;
				state <- "feeding";
				feed_timer <- FEED_DURATION;
				
				// --- Interaction with current pen on arrival ---
				do interact_with_pen;
			} else {
				location <- location + {(target_loc.x - location.x) * (move_speed / dist), (target_loc.y - location.y) * (move_speed / dist)};
			}
		} else if (state = "feeding") {
			feed_timer <- feed_timer - 1;
			if (feed_timer <= 0) {
				// Finished feeding at current pen -> advance to next pen
				state <- "moving";
				if (moving_forward) {
					if (current_pen_idx >= NUM_PENS - 1) {
						moving_forward <- false;
						current_pen_idx <- max(0, NUM_PENS - 2);
					} else {
						current_pen_idx <- current_pen_idx + 1;
					}
				} else {
					if (current_pen_idx <= 0) {
						moving_forward <- true;
						current_pen_idx <- min(1, NUM_PENS - 1);
					} else {
						current_pen_idx <- current_pen_idx - 1;
					}
				}
			}
		}
	}

	action interact_with_pen {
		if (current_pen_idx < 0 or current_pen_idx >= length(PigPen)) {
			return;
		}
		PigPen cur_pen <- PigPen[current_pen_idx];
		bool pen_has_sick_pigs <- (cur_pen.exposed_count > 0 or cur_pen.infected_count > 0);

		// 1. Contamination: If pen is infected, farmer can pick up pathogen
		if (pen_has_sick_pigs) {
			if (!has_pathogen) {
				float b <- rnd(0.402, 1.85);
				if (flip(1 - e ^ -b)) {
					has_pathogen <- true;
				}
			}
		} 
		// 2. Transmission: If farmer carries pathogen and pen is currently healthy, farmer can transmit disease
		else if (has_pathogen) {
			float b <- rnd(0.402, 1.85);
			if (flip(1 - e ^ -b)) {
				// Expose susceptible pigs in this pen
				list<FarmPig> susceptible_pigs <- cur_pen.my_pigs where (each.seir = 0 and each.recover_count = 0);
				if (!empty(susceptible_pigs)) {
					FarmPig victim <- one_of(susceptible_pigs);
					victim.seir <- 1;
					victim.infection_source <- "farmer";
					victim.expose_count_per_day <- victim.expose_count_per_day + 1;
				}
				// Contaminate troughs with food disease in this pen
				cur_pen.pen_type <- "Food Disease";
				point my_origin <- cur_pen.pen_origin;
				loop j from: 0 to: 4 {
					point t_loc <- my_origin + trough_locs[j];
					create FoodDiseaseFactor number: 1 {
						duration <- 7 * 24 * 60;
						size <- 2.0;
						location <- t_loc;
					}
				}
			}
		}
	}

	aspect macro {
		// Halo circle showing health/carrier status
		if (has_pathogen) {
			draw circle(7.0) color: rgb(255, 60, 60, 100) border: rgb(220, 30, 30) width: 2;
			draw "CARRIER" at: {location.x, location.y - 7.0} color: rgb(255, 80, 80) font: font("Arial", 7, #bold) anchor: #center;
		} else {
			draw circle(6.0) color: rgb(60, 220, 60, 70) border: rgb(40, 180, 40) width: 1;
			draw "CLEAN" at: {location.x, location.y - 7.0} color: rgb(100, 230, 100) font: font("Arial", 6, #plain) anchor: #center;
		}
		// Farmer sprite
		draw farmer_img size: 10.0;
	}

	aspect detail {
		if (selected_pen != nil and current_pen_idx = (PigPen(selected_pen).pen_id - 1)) {
			if (has_pathogen) {
				draw circle(7.0) color: rgb(255, 60, 60, 100) border: rgb(220, 30, 30) width: 2;
				draw "CARRIER" at: {location.x, location.y - 7.0} color: rgb(255, 80, 80) font: font("Arial", 7, #bold) anchor: #center;
			} else {
				draw circle(6.0) color: rgb(60, 220, 60, 70) border: rgb(40, 180, 40) width: 1;
				draw "CLEAN" at: {location.x, location.y - 7.0} color: rgb(100, 230, 100) font: font("Arial", 6, #plain) anchor: #center;
			}
			draw farmer_img size: 10.0;
		}
	}
}


// =====================================================================
//                   PENTROUGH SPECIES (UNIFIED TROUGH)
// =====================================================================
species PenTrough parent: Trough {
	int pen_id;

	aspect base {
		draw rectangle(3.0, 8.0) color: rgb(55, 115, 215) border: rgb(35, 80, 170);
	}

	aspect detail {
		if (selected_pen != nil and pen_id = PigPen(selected_pen).pen_id) {
			draw rectangle(3.0, 8.0) color: rgb(55, 115, 215) border: rgb(35, 80, 170);
		}
	}
}


// =====================================================================
//                          EXPERIMENT
// =====================================================================
/**
 * TwoLayerFarm experiment.
 *
 * HOW TO USE:
 *   1. Set parameters in the panel on the left:
 *      - Number of Pens (1-50)
 *      - Pens per Row (1-10)
 *      - Disease Probability (%) or manual Disease Pens list
 *   2. Click the "Set Configuration" button to build the farm.
 *   3. Click Play to start the simulation.
 *   4. You can click "Set Configuration" again to rebuild with new settings.
 */
experiment TwoLayerFarm type: gui {

	// ==================== PRE-SIMULATION PARAMETERS ====================
	parameter "Number of Pens (1-50)" var: NUM_PENS min: 1 max: 50 init: 5 category: "Farm Setup";
	parameter "Pens per Row (1-10)" var: PENS_PER_ROW min: 1 max: 10 init: 5 category: "Farm Setup";
	parameter "Initial Infected Pen (1-50)" var: initial_infected_pen min: 1 max: 50 init: 1 category: "Disease Settings";

	// ==================== SET CONFIGURATION BUTTON ====================
	user_command "Set Configuration" {
		ask simulation {
			do setup_farm;
		}
	}

	// ==================== MOUSE CLICK HANDLER ====================
	action select_pen_click {
		point loc <- #user_location;
		loop pen over: PigPen {
			point origin <- pen.pen_origin;
			if (loc.x >= origin.x and loc.x <= origin.x + PEN_WIDTH
				and loc.y >= origin.y and loc.y <= origin.y + PEN_HEIGHT) {
				selected_pen <- pen;
				// Jump camera to selected pen, then unlock for manual mouse zoom
				detail_cam_x <- pen.location.x;
				detail_cam_y <- pen.location.y;
				detail_cam_z <- 130.0;
				detail_cam_dynamic <- true;
				break;
			}
		}
	}

	output {
		layout horizontal([0::5000, 1::5000]) tabs: false;


		// ==================== LAYER 1: FARM OVERVIEW ====================
		display "Farm Overview" type: opengl axes: false antialias: true background: rgb(38, 45, 38) {

			// Camera dynamically scales to show all pens (up to 50 pens) then unlocks for manual zoom
			camera #default location: {overview_cam_x, overview_cam_y, overview_cam_z}
				   target: {overview_cam_x, overview_cam_y, 0.0} dynamic: overview_cam_dynamic;

			// PigPen backgrounds + stats
			species PigPen aspect: macro;

			// Pig sprites (no text in overview)
			species FarmPig aspect: macro;

			// Caretaker / Farmer agent
			species Farmer aspect: macro;

			// Partition walls between adjacent pens (same row only)
			graphics "partition_walls" {
				int pen_count <- length(PEN_ORIGINS);
				loop i from: 0 to: pen_count - 2 {
					int row_i <- int(i / PENS_PER_ROW);
					int row_next <- int((i + 1) / PENS_PER_ROW);

					if (row_i = row_next) {
						float wall_x <- PEN_ORIGINS[i].x + PEN_WIDTH + PEN_GAP / 2.0;
						float wall_y <- PEN_ORIGINS[i].y;

						bool disease_active <- false;
						loop pen over: PigPen {
							if ((pen.pen_id = i + 1 or pen.pen_id = i + 2)
								and (pen.exposed_count > 0 or pen.infected_count > 0)) {
								disease_active <- true;
							}
						}
						rgb wall_color <- disease_active ? rgb(220, 70, 50) : rgb(110, 95, 75);
						draw line([{wall_x, wall_y}, {wall_x, wall_y + PEN_HEIGHT}])
							 color: wall_color width: 2;
					}
				}
			}

			// Overlay: simulation summary (top-left)
			overlay position: {5, 5} size: {280, 95} background: rgb(28, 35, 28) transparency: 0.15 {
				int days <- int(cycle / (24 * 60));
				int hours <- (cycle / 60) mod 24;
				int mins <- cycle mod 60;

				draw "PIG FARM SIMULATOR"
					 at: {10, 16} color: rgb(255, 210, 120) font: font("Arial", 12, #bold);
				draw "Day " + days + "  " + (hours < 10 ? "0" : "") + hours + ":" + (mins < 10 ? "0" : "") + mins
					 at: {10, 34} color: rgb(240, 238, 230) font: font("Arial", 13, #bold);
				draw "Pens: " + length(PigPen) + "  |  Grid: " + num_cols + " x " + num_rows
					 at: {10, 52} color: rgb(170, 185, 160) font: font("Arial", 10, #plain);
				int total_e <- int(PigPen sum_of (each.exposed_count));
				int total_i <- int(PigPen sum_of (each.infected_count));
				int total_r <- int(PigPen sum_of (each.recovered_count));
				draw "Exposed:" + total_e + "  Infected:" + total_i + "  Recovered:" + total_r
					 at: {10, 68} color: rgb(255, 185, 110) font: font("Arial", 10, #plain);

				if (length(Farmer) > 0) {
					Farmer fm <- Farmer[0];
					string fm_status <- fm.has_pathogen ? "CARRIER (INFECTED)" : "CLEAN";
					rgb fm_color <- fm.has_pathogen ? rgb(255, 90, 80) : rgb(120, 240, 120);
					draw "Farmer: Pen " + (fm.current_pen_idx + 1) + " [" + fm.state + "] - " + fm_status
						 at: {10, 84} color: fm_color font: font("Arial", 10, #bold);
				}
			}

			// Instruction text when farm not yet initialized
			graphics "init_message" {
				if (!farm_initialized) {
					draw "Set parameters on the left panel, then click"
						 at: {ENV_WIDTH / 2.0, ENV_HEIGHT / 2.0 - 10}
						 color: rgb(200, 210, 180) font: font("Arial", 14, #bold) anchor: #center;
					draw "'Set Configuration' to build the farm"
						 at: {ENV_WIDTH / 2.0, ENV_HEIGHT / 2.0 + 14}
						 color: rgb(160, 170, 145) font: font("Arial", 12, #plain) anchor: #center;
				}
			}

			event mouse_down action: select_pen_click;
		}


		// ==================== LAYER 2: PIG PEN DETAIL ====================
		display "Pig Pen Detail" type: opengl axes: false antialias: true background: rgb(28, 32, 40) {

			// Camera zooms into selected pen, then unlocks for manual mouse zoom
			camera #default location: {detail_cam_x, detail_cam_y, detail_cam_z}
				   target: {detail_cam_x, detail_cam_y, 0.0} dynamic: detail_cam_dynamic;

			// Background image of selected pen (always non-flipped)
			graphics "detail_background" {
				if (selected_pen = nil) {
					draw "Select a pen from Farm Overview"
						 at: {ENV_WIDTH / 2.0, ENV_HEIGHT / 2.0}
						 color: rgb(120, 135, 155) font: font("Arial", 14, #bold) anchor: #center;
					draw "Click on any pen to view details"
						 at: {ENV_WIDTH / 2.0, ENV_HEIGHT / 2.0 + 18}
						 color: rgb(90, 100, 115) font: font("Arial", 11, #plain) anchor: #center;
				} else {
					PigPen sp <- PigPen(selected_pen);

					draw pen_bg_img size: {PEN_WIDTH, PEN_HEIGHT} at: sp.location;

					// Golden selection border
					draw rectangle(PEN_WIDTH + 2.0, PEN_HEIGHT + 2.0) at: sp.location
						 color: rgb(0, 0, 0, 0) border: rgb(255, 200, 50) width: 2;
				}
			}

			// Pig and trough agents (filtered to selected pen only)
			species FarmPig aspect: detail;
			species PenTrough aspect: detail;
			species Farmer aspect: detail;

			// Grid overlay on selected pen
			graphics "detail_grid" {
				if (selected_pen != nil) {
					PigPen sp <- PigPen(selected_pen);
					point origin <- sp.pen_origin;
					rgb grid_color <- rgb(255, 255, 255, 25);

					loop gx from: 0 to: int(PEN_WIDTH) step: 10 {
						draw line([{origin.x + gx, origin.y}, {origin.x + gx, origin.y + PEN_HEIGHT}])
							 color: grid_color width: 1;
					}
					loop gy from: 0 to: int(PEN_HEIGHT) step: 10 {
						draw line([{origin.x, origin.y + gy}, {origin.x + PEN_WIDTH, origin.y + gy}])
							 color: grid_color width: 1;
					}
				}
			}

			// Detail overlay (pen info + disease stats)
			overlay position: {5, 5} size: {240, 120} background: rgb(22, 28, 38) transparency: 0.1 {
				if (selected_pen != nil) {
					PigPen sp <- PigPen(selected_pen);

					// Pen title
					draw "Pen " + sp.pen_id
						 at: {10, 18} color: rgb(255, 210, 120) font: font("Arial", 16, #bold);

					// Type
					rgb type_c <- sp.pen_type = "Food Disease" ? rgb(255, 160, 80) : rgb(160, 175, 190);
					draw sp.pen_type
						 at: {10, 38} color: type_c font: font("Arial", 11, #plain);

					// Time
					int d <- int(cycle / (24 * 60));
					int h <- (cycle / 60) mod 24;
					int m <- cycle mod 60;
					draw "Day " + d + "  " + (h < 10 ? "0" : "") + h + ":" + (m < 10 ? "0" : "") + m
						 at: {10, 56} color: rgb(210, 215, 225) font: font("Arial", 12, #bold);

					// Pig count + weight
					draw "Pigs: " + sp.pig_count + "  |  Weight: " + (sp.total_weight with_precision 1) + " kg"
						 at: {10, 76} color: rgb(190, 200, 210) font: font("Arial", 10, #plain);

					// Disease stats
					draw "E:" + sp.exposed_count + "  I:" + sp.infected_count + "  R:" + sp.recovered_count
						 at: {10, 94} color: rgb(255, 185, 110) font: font("Arial", 10, #plain);
				} else {
					draw "No pen selected"
						 at: {10, 25} color: rgb(100, 115, 135) font: font("Arial", 12, #plain);
				}
			}
		}
	}
}
