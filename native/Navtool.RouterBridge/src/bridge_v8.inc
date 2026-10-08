// Included in the bridge translation unit to share the frozen v7 translators.
struct navtool_router_polar_v8 {
    sailroute::VesselPolar polar;
    navtool_router_polar_options_v8 requested;
    bool demo;
};

struct navtool_router_land_v8 {
    sailroute::SignedDistanceLandmask mask;
    navtool_router_land_options_v8 options;
};

namespace {

navtool_router_status_v1 error_v8(const sailroute::Error& error) {
    if (error.code == sailroute::ErrorCode::invalid_polar)
        return fail(NAVTOOL_ROUTER_STATUS_INVALID_POLAR_V8, error.message);
    if (error.code == sailroute::ErrorCode::cancelled)
        return fail(NAVTOOL_ROUTER_STATUS_CANCELLED_V8, error.message);
    return map_error(error);
}

bool utf8_valid(const char* text) {
    if (!text) return false;
    const auto* p = reinterpret_cast<const unsigned char*>(text);
    while (*p) {
        const unsigned char first = *p++;
        if (first < 0x80) continue;
        unsigned int count = 0;
        uint32_t value = 0;
        uint32_t minimum = 0;
        if (first >= 0xc2 && first <= 0xdf) { count = 1; value = first & 0x1f; minimum = 0x80; }
        else if (first >= 0xe0 && first <= 0xef) { count = 2; value = first & 0x0f; minimum = 0x800; }
        else if (first >= 0xf0 && first <= 0xf4) { count = 3; value = first & 7; minimum = 0x10000; }
        else return false;
        for (unsigned int i = 0; i < count; ++i) {
            if ((*p & 0xc0) != 0x80) return false;
            value = (value << 6) | (*p++ & 0x3f);
        }
        if (value < minimum || value > 0x10ffff || (value >= 0xd800 && value <= 0xdfff)) return false;
    }
    return true;
}

std::string json_string(std::string_view text) {
    std::ostringstream out;
    out << '"';
    for (char character : text) {
        const auto c = static_cast<unsigned char>(character);
        if (c == '"' || c == '\\') out << '\\' << static_cast<char>(c);
        else if (c < 0x20) out << "\\u" << std::hex << std::setw(4) << std::setfill('0') << static_cast<unsigned int>(c);
        else out << static_cast<char>(c);
    }
    out << '"';
    return out.str();
}

bool json_outputs(char** text, size_t* length) {
    if (text) *text = nullptr;
    if (length) *length = 0;
    return text && length;
}

std::filesystem::path utf8_path(const char* text) {
    return std::filesystem::path{std::u8string{reinterpret_cast<const char8_t*>(text)}};
}

bool positive(double x) { return std::isfinite(x) && x > 0; }
bool nonnegative(double x) { return std::isfinite(x) && x >= 0; }

navtool_router_options_v6 export_common(const sailroute::RoutingOptions& o) {
    navtool_router_options_v6 result{};
    result.solver = static_cast<int32_t>(o.solver);
    result.heading_augmentation = static_cast<int32_t>(o.heading_augmentation);
    result.wind_sampling = static_cast<int32_t>(o.wind_sampling);
    result.polar_angle_interpolation = static_cast<int32_t>(o.polar_angle_interpolation);
    result.above_polar_range = static_cast<int32_t>(o.above_polar_range);
    result.pruning_strategy = static_cast<int32_t>(o.pruning_strategy);
    result.destination_front_segment_policy = static_cast<int32_t>(o.progress.destination_front.segment_policy);
    result.lattice_search_algorithm = static_cast<int32_t>(o.lattice.search_algorithm);
    result.tack_penalty_seconds = o.maneuver.tack_penalty.count();
    result.gybe_penalty_seconds = o.maneuver.gybe_penalty.count();
    result.midpoint_wind_sampling_threshold_minutes = o.midpoint_wind_sampling_threshold.count();
    result.lattice_time_bucket_minutes = o.lattice.time_bucket.count();
    result.downwind_true_wind_angle_degrees = o.maneuver.downwind_true_wind_angle_degrees;
    result.maximum_true_wind_speed_knots = o.maximum_true_wind_speed_knots.value_or(0);
    result.pruning_sector_degrees = o.pruning_sector_degrees;
    result.destination_front_half_angle_degrees = o.progress.destination_front.half_angle_degrees;
    result.lattice_corridor_width_nautical_miles = o.lattice.corridor_width_nautical_miles;
    result.destination_front_minimum_secondary_segment_points = o.progress.destination_front.minimum_secondary_segment_points;
    result.lattice_subdivision_level = o.lattice.subdivision_level;
    result.lattice_refinement_levels = o.lattice.refinement_levels;
    result.lattice_corridor_widening_retries = o.lattice.corridor_widening_retries;
    result.lattice_progress_every_n_expansions = o.lattice.progress_every_n_expansions;
    result.flags = o.maximum_true_wind_speed_knots ? NAVTOOL_ROUTER_OPTIONS_HAS_MAXIMUM_TRUE_WIND_SPEED_V6 : 0;
    return result;
}

navtool_router_options_v8 export_options(const sailroute::RoutingOptions& o, int32_t quality) {
    navtool_router_options_v8 result{};
    result.struct_size = sizeof(result);
    result.quality = quality;
    result.override_flags = NAVTOOL_ROUTER_OVERRIDE_ALL_V8;
    result.common = export_common(o);
    result.time_step_minutes = o.time_step.count();
    result.maximum_route_duration_hours = o.maximum_route_duration.count();
    result.maximum_integration_step_minutes = o.maximum_integration_step.count();
    result.heading_step_degrees = o.heading_step_degrees;
    result.spatial_bucket_nautical_miles = o.spatial_bucket_nautical_miles;
    result.arrival_radius_nautical_miles = o.arrival_radius_nautical_miles;
    result.minimum_boat_speed_knots = o.minimum_boat_speed_knots;
    result.boat_speed_factor = o.boat_speed_factor;
    result.max_nodes_per_bucket = o.max_nodes_per_bucket;
    result.worker_count = o.worker_count;
    result.maximum_generated_candidates = o.maximum_generated_candidates;
    result.maximum_retained_nodes = o.maximum_retained_nodes;
    result.progress_every_n_steps = o.progress.every_n_steps;
    result.use_routing_intervals = o.use_routing_intervals;
    result.strategic_retention = o.strategic_retention;
    result.capture_isochrones = o.capture_isochrones;
    result.destination_front_mode = static_cast<int32_t>(o.progress.destination_front.mode);
    if (o.routing_intervals.size() > NAVTOOL_ROUTER_MAX_INTERVALS_V8)
        throw std::runtime_error("native quality intervals exceed ABI capacity");
    result.interval_count = static_cast<uint32_t>(o.routing_intervals.size());
    for (std::size_t i = 0; i < o.routing_intervals.size(); ++i)
        result.intervals[i] = {o.routing_intervals[i].interval.count(), o.routing_intervals[i].until_elapsed ? o.routing_intervals[i].until_elapsed->count() : -1};
    return result;
}

navtool_router_status_v1 resolve_options(const navtool_router_options_v8* in, sailroute::RoutingOptions& o) {
    if (!in || in->struct_size != sizeof(*in) || !valid_v6_enum(in->quality, 2) ||
        in->reserved || (in->override_flags & ~uint64_t{NAVTOOL_ROUTER_OVERRIDE_ALL_V8}))
        return fail(NAVTOOL_ROUTER_STATUS_INVALID_ARGUMENT_V1, "v8 options have invalid size, quality, reserved fields, or override flags");
    o = sailroute::routing_options_for_quality(static_cast<sailroute::RoutingQuality>(in->quality));
    const auto has = [&](uint64_t flag) { return (in->override_flags & flag) != 0; };
    if (has(NAVTOOL_ROUTER_OVERRIDE_COMMON_V8)) {
        auto status = apply_options_v6(in->common, o);
        if (status) return status;
    }
    if (has(NAVTOOL_ROUTER_OVERRIDE_TIME_STEP_V8)) o.time_step = std::chrono::minutes{in->time_step_minutes};
    if (has(NAVTOOL_ROUTER_OVERRIDE_INTERVALS_V8)) {
        if (in->use_routing_intervals > 1 || in->interval_count > NAVTOOL_ROUTER_MAX_INTERVALS_V8)
            return fail(NAVTOOL_ROUTER_STATUS_INVALID_ARGUMENT_V1, "invalid routing interval count or enable flag");
        o.use_routing_intervals = in->use_routing_intervals != 0;
        o.routing_intervals.clear();
        int64_t previous = 0;
        for (uint32_t i = 0; i < in->interval_count; ++i) {
            const auto& tier = in->intervals[i];
            if (tier.interval_minutes < 5 || tier.interval_minutes > 1440 ||
                (tier.until_elapsed_minutes == -1 ? i + 1 != in->interval_count : tier.until_elapsed_minutes <= previous) ||
                tier.until_elapsed_minutes > 366 * 24 * 60)
                return fail(NAVTOOL_ROUTER_STATUS_INVALID_ARGUMENT_V1, "routing intervals must have positive bounded durations and increasing expiry, with only the last tier unbounded");
            o.routing_intervals.push_back({std::chrono::minutes{tier.interval_minutes},
                tier.until_elapsed_minutes == -1 ? std::nullopt : std::optional{std::chrono::minutes{tier.until_elapsed_minutes}}});
            previous = tier.until_elapsed_minutes;
        }
        if (o.use_routing_intervals && (o.routing_intervals.empty() || o.routing_intervals.back().until_elapsed))
            return fail(NAVTOOL_ROUTER_STATUS_INVALID_ARGUMENT_V1, "enabled intervals require a final unbounded tier");
    }
    if (has(NAVTOOL_ROUTER_OVERRIDE_SEARCH_GEOMETRY_V8)) {
        o.heading_step_degrees = in->heading_step_degrees;
        o.spatial_bucket_nautical_miles = in->spatial_bucket_nautical_miles;
    }
    if (has(NAVTOOL_ROUTER_OVERRIDE_BUCKET_CAPACITY_V8)) {
        if (!fits_size_t(in->max_nodes_per_bucket)) return fail(NAVTOOL_ROUTER_STATUS_INVALID_ARGUMENT_V1, "bucket capacity overflow");
        o.max_nodes_per_bucket = static_cast<size_t>(in->max_nodes_per_bucket);
    }
    if (has(NAVTOOL_ROUTER_OVERRIDE_WORKERS_V8)) {
        if (in->worker_count > 1024) return fail(NAVTOOL_ROUTER_STATUS_INVALID_ARGUMENT_V1, "worker count exceeds bridge bound of 1024");
        o.worker_count = static_cast<size_t>(in->worker_count);
    }
    if (has(NAVTOOL_ROUTER_OVERRIDE_DURATION_V8)) o.maximum_route_duration = std::chrono::hours{in->maximum_route_duration_hours};
    if (has(NAVTOOL_ROUTER_OVERRIDE_MINIMUM_SPEED_V8)) o.minimum_boat_speed_knots = in->minimum_boat_speed_knots;
    if (has(NAVTOOL_ROUTER_OVERRIDE_INTEGRATION_V8)) o.maximum_integration_step = std::chrono::minutes{in->maximum_integration_step_minutes};
    if (has(NAVTOOL_ROUTER_OVERRIDE_BOAT_FACTOR_V8)) o.boat_speed_factor = in->boat_speed_factor;
    if (has(NAVTOOL_ROUTER_OVERRIDE_ARRIVAL_V8)) o.arrival_radius_nautical_miles = in->arrival_radius_nautical_miles;
    if (has(NAVTOOL_ROUTER_OVERRIDE_BUDGETS_V8)) {
        if (!fits_size_t(in->maximum_generated_candidates) || !fits_size_t(in->maximum_retained_nodes))
            return fail(NAVTOOL_ROUTER_STATUS_INVALID_ARGUMENT_V1, "search budget overflow");
        o.maximum_generated_candidates = static_cast<size_t>(in->maximum_generated_candidates);
        o.maximum_retained_nodes = static_cast<size_t>(in->maximum_retained_nodes);
    }
    if (has(NAVTOOL_ROUTER_OVERRIDE_STRATEGIC_RETENTION_V8)) {
        if (in->strategic_retention > 1) return fail(NAVTOOL_ROUTER_STATUS_INVALID_ARGUMENT_V1, "invalid strategic retention flag");
        o.strategic_retention = in->strategic_retention != 0;
    }
    if (has(NAVTOOL_ROUTER_OVERRIDE_PROGRESS_V8)) {
        if (!fits_size_t(in->progress_every_n_steps) || in->capture_isochrones > 1 || !valid_v6_enum(in->destination_front_mode, 1))
            return fail(NAVTOOL_ROUTER_STATUS_INVALID_ARGUMENT_V1, "invalid progress options");
        o.progress.every_n_steps = static_cast<size_t>(in->progress_every_n_steps);
        o.capture_isochrones = in->capture_isochrones != 0;
        o.progress.destination_front.mode = static_cast<sailroute::DestinationFrontMode>(in->destination_front_mode);
    }
    // Check before chrono conversions/allocation/search. These are input bounds,
    // not independently-maintained quality preset constants.
    if (o.time_step.count() < 5 || o.time_step.count() > 1440 ||
        o.maximum_route_duration.count() <= 0 || o.maximum_route_duration.count() > 366 * 24 ||
        o.maximum_integration_step.count() <= 0 || o.maximum_integration_step.count() > 1440 ||
        !positive(o.heading_step_degrees) || o.heading_step_degrees > 180 || 360 / o.heading_step_degrees > 1000000 ||
        !positive(o.spatial_bucket_nautical_miles) || !positive(o.arrival_radius_nautical_miles) ||
        !nonnegative(o.minimum_boat_speed_knots) || !positive(o.boat_speed_factor) ||
        !o.max_nodes_per_bucket || !o.maximum_generated_candidates || !o.maximum_retained_nodes ||
        !o.progress.every_n_steps || o.maneuver.tack_penalty.count() < 0 || o.maneuver.gybe_penalty.count() < 0 ||
        o.maneuver.tack_penalty.count() > 366 * 86400 || o.maneuver.gybe_penalty.count() > 366 * 86400 ||
        !nonnegative(o.maneuver.downwind_true_wind_angle_degrees) || o.maneuver.downwind_true_wind_angle_degrees > 180 ||
        o.midpoint_wind_sampling_threshold.count() < 0 || o.midpoint_wind_sampling_threshold.count() > 366 * 1440 ||
        (o.maximum_true_wind_speed_knots && !positive(*o.maximum_true_wind_speed_knots)) ||
        !positive(o.pruning_sector_degrees) || o.pruning_sector_degrees > 180 ||
        !positive(o.progress.destination_front.half_angle_degrees) || o.progress.destination_front.half_angle_degrees > 180 ||
        !o.progress.destination_front.minimum_secondary_segment_points ||
        o.lattice.time_bucket.count() <= 0 || o.lattice.time_bucket.count() > 1440 ||
        !positive(o.lattice.corridor_width_nautical_miles) || !o.lattice.progress_every_n_expansions ||
        o.lattice.subdivision_level > 8 || o.lattice.refinement_levels > 8 - o.lattice.subdivision_level ||
        o.lattice.corridor_widening_retries > 64 ||
        (o.solver == sailroute::RoutingSolver::time_dependent_lattice && o.capture_isochrones))
        return fail(NAVTOOL_ROUTER_STATUS_INVALID_ARGUMENT_V1, "invalid v8 numerical, timing, budget, progress, or lattice settings");
    return NAVTOOL_ROUTER_STATUS_OK_V1;
}

navtool_router_status_v1 estimate_land(const navtool_router_land_options_v8* o, navtool_router_land_estimate_v8& e) {
    if (!o || o->struct_size != sizeof(*o) || o->reserved ||
        !valid_bounds(o->south_latitude_degrees, o->west_longitude_degrees, o->north_latitude_degrees, o->east_longitude_degrees))
        return fail(NAVTOOL_ROUTER_STATUS_INVALID_ARGUMENT_V1, "invalid GSHHG options or bounds");
    const double lat_span = o->north_latitude_degrees - o->south_latitude_degrees;
    double lon_span = o->east_longitude_degrees - o->west_longitude_degrees;
    if (lon_span < 0) lon_span += 360;
    if (o->south_latitude_degrees < -85 || o->north_latitude_degrees > 85 ||
        lat_span <= 0 || lat_span > 120 || lon_span <= 0 || lon_span > 120 ||
        !positive(o->resolution_nautical_miles) || o->resolution_nautical_miles < .05 || o->resolution_nautical_miles > 120 ||
        !positive(o->distance_cap_nautical_miles) || o->distance_cap_nautical_miles < 1 || o->distance_cap_nautical_miles > 600 ||
        o->maximum_grid_nodes < 4 || o->maximum_grid_nodes > 250000 ||
        o->maximum_source_points < 3 || o->maximum_source_points > 10000000 ||
        !o->maximum_geometry_tests || o->maximum_geometry_tests > 100000000)
        return fail(NAVTOOL_ROUTER_STATUS_INVALID_ARGUMENT_V1, "GSHHG regional, spacing, distance cap, or budget bounds exceeded");
    // Exact arithmetic of pinned land_data.cpp::make_region, not the managed
    // SDF builder's half-diagonal. Preview cannot inspect source completeness.
    constexpr double nm_degree = 3440.065 * (std::numbers::pi / 180);
    constexpr double numerical = 1.0e-5;
    const double step = o->resolution_nautical_miles / nm_degree;
    const double rows = std::ceil(lat_span / step) + 1;
    const double columns = std::ceil(lon_span / step) + 1;
    e = {};
    e.struct_size = sizeof(e);
    e.latitude_count = static_cast<uint64_t>(rows);
    e.longitude_count = static_cast<uint64_t>(columns);
    e.grid_nodes = e.latitude_count * e.longitude_count;
    e.latitude_step_degrees = lat_span / (rows - 1);
    e.longitude_step_degrees = lon_span / (columns - 1);
    e.interpolation_error_nautical_miles = nm_degree * (e.latitude_step_degrees + e.longitude_step_degrees) + numerical;
    const double halo = (o->distance_cap_nautical_miles + numerical) / nm_degree;
    e.halo_south_latitude_degrees = o->south_latitude_degrees - halo;
    e.halo_north_latitude_degrees = o->north_latitude_degrees + halo;
    const double lon_halo = halo / std::cos(std::max(std::abs(e.halo_south_latitude_degrees), std::abs(e.halo_north_latitude_degrees)) * std::numbers::pi / 180);
    e.halo_west_longitude_degrees = o->west_longitude_degrees - lon_halo;
    e.halo_east_longitude_degrees = o->west_longitude_degrees + lon_span + lon_halo;
    if (rows * columns > static_cast<double>(o->maximum_grid_nodes))
        return fail(NAVTOOL_ROUTER_STATUS_RESOURCE_LIMIT_V8, "GSHHG grid exceeds maximum_grid_nodes; select coarser spacing or explicit smaller study bounds");
    if (o->distance_cap_nautical_miles <= e.interpolation_error_nautical_miles)
        return fail(NAVTOOL_ROUTER_STATUS_INVALID_ARGUMENT_V1, "GSHHG distance cap must exceed full-cell interpolation error");
    if (e.halo_south_latitude_degrees <= -90 || e.halo_north_latitude_degrees >= 90)
        return fail(NAVTOOL_ROUTER_STATUS_INVALID_ARGUMENT_V1, "GSHHG halo reaches unsupported pole");
    return NAVTOOL_ROUTER_STATUS_OK_V1;
}

bool valid_metadata_strings(const navtool_router_provider_metadata_v7& m) {
    return (!m.name_utf8 || utf8_valid(m.name_utf8)) && (!m.source_utf8 || utf8_valid(m.source_utf8)) && (!m.revision_utf8 || utf8_valid(m.revision_utf8));
}

template<size_t N> bool zero_bytes(const uint8_t (&bytes)[N]) {
    return std::all_of(std::begin(bytes), std::end(bytes), [](uint8_t value) { return value == 0; });
}

bool valid_grid_flags(const navtool_router_grid_spec_v7& grid) {
    return grid.global_longitude_coverage <= 1 && zero_bytes(grid.reserved);
}

bool valid_exclusion_text(const navtool_router_exclusion_settings_v7& e) {
    if (!valid_metadata_strings(e.metadata) || e.configured > 1 || !zero_bytes(e.reserved)) return false;
    if (e.zones) {
        for (uint64_t i = 0; i < e.zone_count; ++i) {
            if (!utf8_valid(e.zones[i].identifier_utf8) ||
                (e.zones[i].source_utf8 && !utf8_valid(e.zones[i].source_utf8)) ||
                e.zones[i].has_active_from > 1 || e.zones[i].has_active_until > 1 || !zero_bytes(e.zones[i].reserved) ||
                (e.zones[i].has_active_from && (e.zones[i].active_from_utc_epoch_seconds < -62135596800LL || e.zones[i].active_from_utc_epoch_seconds > 253370764800LL)) ||
                (e.zones[i].has_active_until && (e.zones[i].active_until_utc_epoch_seconds < -62135596800LL || e.zones[i].active_until_utc_epoch_seconds > 253370764800LL)))
                return false;
        }
    }
    return true;
}

navtool_router_status_v1 prepare_request(
    const navtool_router_request_v8* in, sailroute::RouteRequest& request, sailroute::RoutingEnvironment& environment,
    navtool_router_segment_eligibility_callback_v1 eligible, void* user_data) {
    if (!in || in->struct_size != sizeof(*in) || in->reserved || (in->flags & ~1U) ||
        !in->forecast || !in->polar || !in->options ||
        !valid_coordinate(in->start.latitude_degrees, in->start.longitude_degrees) ||
        !valid_coordinate(in->destination.latitude_degrees, in->destination.longitude_degrees))
        return fail(NAVTOOL_ROUTER_STATUS_INVALID_ARGUMENT_V1, "v8 request requires exact size, explicit forecast/polar/options, known flags, and canonical endpoints");
    auto status = resolve_options(in->options, request.options);
    if (status) return status;
    request.start = {in->start.latitude_degrees, in->start.longitude_degrees};
    request.destination = {in->destination.latitude_degrees, in->destination.longitude_degrees};
    if (in->flags & 1) {
        // Bound externally supplied timestamps before downstream chrono arithmetic.
        if (in->departure_utc_epoch_seconds < -62135596800LL || in->departure_utc_epoch_seconds > 253370764800LL)
            return fail(NAVTOOL_ROUTER_STATUS_INVALID_ARGUMENT_V1, "departure time must be within supported UTC years 1..9998");
        request.departure_time = from_epoch(in->departure_utc_epoch_seconds);
    }
    const bool sdf = in->environment && in->environment->land.configured;
    if ((in->land && sdf) || ((in->land || sdf) && eligible))
        return fail(NAVTOOL_ROUTER_STATUS_INVALID_ENVIRONMENT_V7, "native GSHHG/SDF and application segment land owners cannot be combined");
    if (in->environment) {
        const auto& e = *in->environment;
        if (e.reserved || e.land.configured > 1 || !zero_bytes(e.land.reserved) ||
            !valid_grid_flags(e.currents.grid) || !valid_grid_flags(e.waves.grid) || !valid_grid_flags(e.land.grid) ||
            !valid_metadata_strings(e.currents.metadata) || !valid_metadata_strings(e.waves.provider_metadata) ||
            !valid_metadata_strings(e.waves.model_metadata) || !valid_metadata_strings(e.land.metadata) || !valid_exclusion_text(e.exclusions))
            return fail(NAVTOOL_ROUTER_STATUS_INVALID_ENVIRONMENT_V7, "environment metadata is not valid UTF-8 or has invalid flags");
        status = apply_environment_v7(e, environment);
        if (status) return status;
    }
    if (in->land) {
        if (!nonnegative(in->land_clearance_nautical_miles) || !valid_missing_data_policy(in->land_missing_data_policy) ||
            !in->land_maximum_subdivision_depth || in->land_maximum_subdivision_depth > 32)
            return fail(NAVTOOL_ROUTER_STATUS_INVALID_ENVIRONMENT_V7, "invalid GSHHG clearance, subdivision depth, or missing-data policy");
        environment.land.landmask = in->land->mask;
        environment.land.clearance_nautical_miles = in->land_clearance_nautical_miles;
        environment.land.maximum_subdivision_depth = static_cast<size_t>(in->land_maximum_subdivision_depth);
        environment.land.missing_data_policy = to_missing_data_policy(in->land_missing_data_policy);
    } else if (in->land_clearance_nautical_miles != 0 || in->land_maximum_subdivision_depth != 0 || in->land_missing_data_policy != 0)
        return fail(NAVTOOL_ROUTER_STATUS_INVALID_ENVIRONMENT_V7, "GSHHG settings supplied without a land handle");
    if (const auto error = sailroute::validate_environment(environment)) return error_v8(*error);
    if (eligible) request.options.segment_eligibility = [eligible, user_data](const sailroute::RouteSegmentView& segment) {
        const auto parent = copy_coordinate(segment.parent.position);
        const auto candidate = copy_coordinate(segment.candidate.position);
        return eligible(&parent, &candidate, user_data) != 0;
    };
    request.options.progress.payload = sailroute::RoutingProgressPayload::provisional_route |
        (request.options.solver == sailroute::RoutingSolver::time_dependent_lattice
            ? sailroute::RoutingProgressPayload::search_points
            : sailroute::RoutingProgressPayload::display_contours | sailroute::RoutingProgressPayload::destination_front);
    return NAVTOOL_ROUTER_STATUS_OK_V1;
}

sailroute::RoutingProgressDecision deliver_progress(
    const sailroute::RoutingProgressView& p, navtool_router_progress_callback_v8 callback, void* data) {
    std::vector<navtool_router_coordinate_v1> contours, fronts, search;
    std::vector<navtool_router_contour_segment_v2> contour_segments;
    std::vector<navtool_router_front_segment_v3> front_segments;
    std::vector<navtool_router_route_point_v1> points;
    std::vector<navtool_router_route_point_v8> audited;
    for (auto c : p.display_contours.points) contours.push_back(copy_coordinate(c));
    for (auto c : p.destination_front.points) fronts.push_back(copy_coordinate(c));
    for (auto c : p.search_points) search.push_back(copy_coordinate(c));
    for (const auto& s : p.display_contours.segments) contour_segments.push_back({s.point_offset, s.point_count, static_cast<uint8_t>(s.closed), {}});
    for (const auto& s : p.destination_front.segments) front_segments.push_back({s.point_offset, s.point_count});
    for (const auto& point : p.provisional_route) {
        points.push_back(copy_route_point(point));
        navtool_router_route_point_v8 a{};
        a.point = points.back();
        if (point.environment) {
            const auto& e = *point.environment;
            a.flags = 1U | (e.current_applied ? 2U : 0U) | (e.wave_applied ? 4U : 0U);
            a.speed_over_ground_knots = e.speed_over_ground_knots;
            a.course_over_ground_degrees = e.course_over_ground_degrees;
            a.current_east_knots = e.current_east_knots;
            a.current_north_knots = e.current_north_knots;
            a.flat_water_speed_knots = e.flat_water_speed_knots;
            a.significant_wave_height_metres = e.significant_wave_height_metres;
            a.wave_period_seconds = e.wave_period_seconds;
            a.relative_wave_angle_degrees = e.relative_wave_angle_degrees;
            a.polar_wind_speed_knots = e.polar_wind_speed_knots;
            a.polar_wind_direction_degrees = e.polar_wind_direction_degrees;
        }
        audited.push_back(a);
    }
    navtool_router_progress_v8 out{};
    out.struct_size = sizeof(out);
    out.progress = {static_cast<int32_t>(p.solver), 0, to_epoch(p.time),
        contours.data(), contours.size(), contour_segments.data(), contour_segments.size(),
        fronts.data(), fronts.size(), front_segments.data(), front_segments.size(), search.data(), search.size(),
        points.data(), points.size(), copy_diagnostics(p.diagnostics),
        {p.search.settled_labels, p.search.queued_labels, p.search.relaxed_labels, p.search.refinement_index, p.search.subdivision_level}};
    out.audited_route_points = audited.data();
    out.audited_route_point_count = audited.size();
    out.eligibility_evaluations = p.diagnostics.eligibility_evaluations;
    out.pruned_candidates = p.diagnostics.pruned_candidates;
    out.future_probe_misses = p.diagnostics.future_probe_misses;
    return callback(&out, data) ? sailroute::RoutingProgressDecision::continue_routing : sailroute::RoutingProgressDecision::cancel;
}
} // namespace

extern "C" {
navtool_router_status_v1 navtool_router_build_info_v8(char** text, size_t* length) {
    return protect([&]() -> navtool_router_status_v1 {
        if (!json_outputs(text, length)) return fail(NAVTOOL_ROUTER_STATUS_INVALID_ARGUMENT_V1, "build info outputs required");
        std::ostringstream s;
        s << "{\"abi_version\":" << NAVTOOL_ROUTER_BRIDGE_ABI_VERSION
          << ",\"route_json_schema\":\"route_result_v2\",\"library_version\":" << json_string(NAVTOOL_ROUTER_RESOLVED_VERSION)
          << ",\"library_revision\":" << json_string(NAVTOOL_ROUTER_RESOLVED_REVISION)
          << ",\"source_kind\":" << json_string(NAVTOOL_ROUTER_SOURCE_KIND)
          << ",\"source_path\":" << json_string(NAVTOOL_ROUTER_SOURCE_PATH)
          << ",\"source_dirty\":" << json_string(NAVTOOL_ROUTER_SOURCE_DIRTY)
          << ",\"patch_set_sha256\":"
          << (std::string_view{NAVTOOL_ROUTER_PATCH_SET_SHA256}.empty() ? "null" : json_string(NAVTOOL_ROUTER_PATCH_SET_SHA256))
          << ",\"architecture\":" << json_string(NAVTOOL_ROUTER_BUILD_ARCH)
          << ",\"development_snapshot\":" << (std::string_view{NAVTOOL_ROUTER_RESOLVED_REVISION} == "cd476a84ef3edea9582d77f21588a23af727e083" ? "true" : "null")
          << ",\"capabilities\":" << navtool_router_bridge_capabilities_v1()
          << ",\"ensemble_enabled\":"
#ifdef SAILROUTE_ENABLE_ENSEMBLE
          << "true"
#else
          << "false"
#endif
          << ",\"land_data_enabled\":"
#ifdef SAILROUTE_ENABLE_LAND_DATA
          << "true"
#else
          << "false"
#endif
          << "}";
        return copy_utf8(s.str(), text, length);
    });
}

navtool_router_status_v1 navtool_router_quality_defaults_v8(int32_t quality, navtool_router_options_v8* out) {
    return protect([&]() -> navtool_router_status_v1 {
        if (!out || out->struct_size != sizeof(*out) || !valid_v6_enum(quality, 2))
            return fail(NAVTOOL_ROUTER_STATUS_INVALID_ARGUMENT_V1, "defaults require exact output size and supported native quality");
        *out = export_options(sailroute::routing_options_for_quality(static_cast<sailroute::RoutingQuality>(quality)), quality);
        return NAVTOOL_ROUTER_STATUS_OK_V1;
    });
}

navtool_router_status_v1 navtool_router_resolve_options_v8(const navtool_router_options_v8* in, navtool_router_options_v8* out) {
    return protect([&]() -> navtool_router_status_v1 {
        if (!out || out->struct_size != sizeof(*out)) return fail(NAVTOOL_ROUTER_STATUS_INVALID_ARGUMENT_V1, "effective options require exact output size");
        sailroute::RoutingOptions o;
        auto status = resolve_options(in, o);
        if (!status) *out = export_options(o, in->quality);
        return status;
    });
}

navtool_router_status_v1 navtool_router_polar_load_v8(const char* path, const navtool_router_polar_options_v8* o, navtool_router_polar_v8** out) {
    return protect([&]() -> navtool_router_status_v1 {
        if (out) *out = nullptr;
        if (!out || !utf8_valid(path) || !*path || !o || o->struct_size != sizeof(*o) ||
            !valid_v6_enum(o->format, 2) || (o->flags & ~1ULL) ||
            ((o->flags & 1) && (!positive(o->minimum_sailing_angle_degrees) || o->minimum_sailing_angle_degrees > 180)))
            return fail(NAVTOOL_ROUTER_STATUS_INVALID_ARGUMENT_V1, "invalid polar path, format, angle restriction, size, or flags");
        sailroute::PolarLoadOptions options;
        options.format = static_cast<sailroute::PolarFormat>(o->format);
        if (o->flags & 1) options.minimum_sailing_angle_degrees = o->minimum_sailing_angle_degrees;
        auto polar = sailroute::VesselPolar::load(utf8_path(path), options);
        if (!polar) return error_v8(polar.error());
        *out = new navtool_router_polar_v8{std::move(polar.value()), *o, false};
        return NAVTOOL_ROUTER_STATUS_OK_V1;
    });
}

navtool_router_status_v1 navtool_router_polar_create_demo_v8(navtool_router_polar_v8** out) {
    return protect([&]() -> navtool_router_status_v1 {
        if (!out) return fail(NAVTOOL_ROUTER_STATUS_INVALID_ARGUMENT_V1, "polar output required");
        *out = nullptr;
        *out = new navtool_router_polar_v8{sailroute::VesselPolar::default_racer_cruiser_45ft(), {sizeof(navtool_router_polar_options_v8), 0, 0, 0}, true};
        return NAVTOOL_ROUTER_STATUS_OK_V1;
    });
}

navtool_router_status_v1 navtool_router_polar_metadata_v8(const navtool_router_polar_v8* p, char** text, size_t* length) {
    return protect([&]() -> navtool_router_status_v1 {
        if (!json_outputs(text, length) || !p) return fail(NAVTOOL_ROUTER_STATUS_INVALID_ARGUMENT_V1, "polar and metadata outputs required");
        std::ostringstream s; s << std::setprecision(17);
        s << "{\"source\":" << json_string(p->polar.source()) << ",\"demo\":" << (p->demo ? "true" : "false")
          << ",\"requested_format\":" << p->requested.format << ",\"resolved_format\":null"
          << ",\"maximum_tabulated_wind_speed_knots\":" << p->polar.maximum_tabulated_wind_speed_knots()
          << ",\"maximum_boat_speed_knots\":" << p->polar.maximum_boat_speed_knots() << ",\"minimum_sailing_angle_degrees\":";
        if (p->requested.flags & 1) s << p->requested.minimum_sailing_angle_degrees; else s << "null";
        s << ",\"validation\":" << json_string(p->demo
            ? "explicit native demonstration polar; not navigation-certified"
            : "accepted by native VesselPolar parser") << "}";
        return copy_utf8(s.str(), text, length);
    });
}

navtool_router_status_v1 navtool_router_polar_destroy_v8(navtool_router_polar_v8** p) {
    return protect([&]() -> navtool_router_status_v1 {
        if (!p) return fail(NAVTOOL_ROUTER_STATUS_INVALID_ARGUMENT_V1, "polar pointer required");
        delete *p; *p = nullptr; return NAVTOOL_ROUTER_STATUS_OK_V1;
    });
}

navtool_router_status_v1 navtool_router_forecast_load_v8(const char* path, const navtool_router_forecast_options_v8* o, navtool_router_forecast_v1** out) {
    return protect([&]() -> navtool_router_status_v1 {
        if (out) *out = nullptr;
        if (!o || o->struct_size != sizeof(*o) || o->reserved || (o->flags & ~3ULL) || !utf8_valid(path) ||
            ((o->flags & 2) && (o->maximum_interpolation_gap_seconds <= 0 || o->maximum_interpolation_gap_seconds > 366 * 86400)))
            return fail(NAVTOOL_ROUTER_STATUS_INVALID_ARGUMENT_V1, "invalid forecast options, UTF-8 path, or interpolation gap");
        sailroute::WeatherLoadOptions options;
        if (o->flags & 1) {
            if (!valid_bounds(o->south_latitude_degrees, o->west_longitude_degrees, o->north_latitude_degrees, o->east_longitude_degrees))
                return fail(NAVTOOL_ROUTER_STATUS_INVALID_ARGUMENT_V1, "invalid forecast bounds");
            options.bounds = sailroute::GeographicBounds{o->south_latitude_degrees, o->west_longitude_degrees, o->north_latitude_degrees, o->east_longitude_degrees};
        }
        if (o->flags & 2) options.maximum_interpolation_gap = std::chrono::seconds{o->maximum_interpolation_gap_seconds};
        return load_forecast(path, out, [&](const std::filesystem::path& p) { return sailroute::WeatherDataset::load(p, options); });
    });
}

navtool_router_status_v1 navtool_router_forecast_get_metadata_v8(const navtool_router_forecast_v1* f, navtool_router_forecast_metadata_v8* out, char** text, size_t* length) {
    return protect([&]() -> navtool_router_status_v1 {
        if (!json_outputs(text, length) || !f || !out || out->struct_size != sizeof(*out))
            return fail(NAVTOOL_ROUTER_STATUS_INVALID_ARGUMENT_V1, "forecast and sized metadata outputs required");
        const auto& m = f->weather.metadata();
        *out = {sizeof(*out), (m.minimum_time_spacing ? 1U : 0U) | (m.global_longitude_coverage ? 2U : 0U),
            to_epoch(m.initialization_time), to_epoch(m.first_valid_time), to_epoch(m.last_valid_time),
            m.minimum_time_spacing ? m.minimum_time_spacing->count() : 0, m.maximum_time_spacing ? m.maximum_time_spacing->count() : 0,
            m.latitude_count, m.longitude_count, m.geographic_coverage.south_latitude_degrees, m.geographic_coverage.west_longitude_degrees,
            m.geographic_coverage.north_latitude_degrees, m.geographic_coverage.east_longitude_degrees, f->weather.valid_times().size()};
        return copy_utf8(m.source, text, length);
    });
}

navtool_router_status_v1 navtool_router_forecast_valid_times_v8(const navtool_router_forecast_v1* f, int64_t* times, uint64_t capacity, uint64_t* required) {
    return protect([&]() -> navtool_router_status_v1 {
        if (required) *required = 0;
        if (!f || !required) return fail(NAVTOOL_ROUTER_STATUS_INVALID_ARGUMENT_V1, "forecast and required_count required");
        *required = f->weather.valid_times().size();
        if (!times && capacity == 0) return NAVTOOL_ROUTER_STATUS_OK_V1;
        if (!times || capacity < *required) return fail(NAVTOOL_ROUTER_STATUS_INVALID_ARGUMENT_V1, "valid-time output capacity too small");
        for (size_t i = 0; i < f->weather.valid_times().size(); ++i) times[i] = to_epoch(f->weather.valid_times()[i]);
        return NAVTOOL_ROUTER_STATUS_OK_V1;
    });
}

navtool_router_status_v1 navtool_router_land_estimate_v8_fn(const navtool_router_land_options_v8* o, navtool_router_land_estimate_v8* out) {
    return protect([&]() -> navtool_router_status_v1 {
        if (!out || out->struct_size != sizeof(*out)) return fail(NAVTOOL_ROUTER_STATUS_INVALID_ARGUMENT_V1, "sized land estimate output required");
        return estimate_land(o, *out);
    });
}

navtool_router_status_v1 navtool_router_land_load_gshhg_v8(const char* path, const navtool_router_land_options_v8* o, navtool_router_land_v8** out) {
    return protect([&]() -> navtool_router_status_v1 {
        if (out) *out = nullptr;
        if (!out || !utf8_valid(path) || !*path) return fail(NAVTOOL_ROUTER_STATUS_INVALID_ARGUMENT_V1, "land path and output required");
        navtool_router_land_estimate_v8 estimate{};
        auto status = estimate_land(o, estimate);
        if (status) return status;
        sailroute::LandDataOptions options;
        options.bounds = {o->south_latitude_degrees, o->west_longitude_degrees, o->north_latitude_degrees, o->east_longitude_degrees};
        options.resolution_nautical_miles = o->resolution_nautical_miles;
        options.distance_cap_nautical_miles = o->distance_cap_nautical_miles;
        options.maximum_grid_nodes = static_cast<size_t>(o->maximum_grid_nodes);
        options.maximum_source_points = static_cast<size_t>(o->maximum_source_points);
        options.maximum_geometry_tests = static_cast<size_t>(o->maximum_geometry_tests);
        auto land = sailroute::load_gshhg_landmask(utf8_path(path), options);
        if (!land) return error_v8(land.error());
        *out = new navtool_router_land_v8{std::move(land.value()), *o};
        return NAVTOOL_ROUTER_STATUS_OK_V1;
    });
}

navtool_router_status_v1 navtool_router_land_metadata_v8(const navtool_router_land_v8* land, char** text, size_t* length) {
    return protect([&]() -> navtool_router_status_v1 {
        if (!json_outputs(text, length) || !land) return fail(NAVTOOL_ROUTER_STATUS_INVALID_ARGUMENT_V1, "land and metadata outputs required");
        const auto& m = land->mask.metadata();
        const auto& g = land->mask.grid();
        std::ostringstream s; s << std::setprecision(17);
        s << "{\"name\":" << json_string(m.provider.name) << ",\"source\":" << json_string(m.provider.source)
          << ",\"revision\":" << json_string(m.provider.revision) << ",\"resolution_nautical_miles\":" << m.resolution_nautical_miles
          << ",\"interpolation_error_nautical_miles\":" << m.interpolation_error_nautical_miles
          << ",\"latitude_count\":" << g.latitude_count << ",\"longitude_count\":" << g.longitude_count
          << ",\"south_latitude_degrees\":" << land->options.south_latitude_degrees << ",\"west_longitude_degrees\":" << land->options.west_longitude_degrees
          << ",\"north_latitude_degrees\":" << land->options.north_latitude_degrees << ",\"east_longitude_degrees\":" << land->options.east_longitude_degrees
          << ",\"distance_cap_nautical_miles\":" << land->options.distance_cap_nautical_miles
          << ",\"source_completeness_certified\":false,\"limitation\":\"GSHHG is not a nautical chart; omitted shoreline records cannot be detected\"}";
        return copy_utf8(s.str(), text, length);
    });
}

navtool_router_status_v1 navtool_router_land_destroy_v8(navtool_router_land_v8** land) {
    return protect([&]() -> navtool_router_status_v1 {
        if (!land) return fail(NAVTOOL_ROUTER_STATUS_INVALID_ARGUMENT_V1, "land pointer required");
        delete *land; *land = nullptr; return NAVTOOL_ROUTER_STATUS_OK_V1;
    });
}

navtool_router_status_v1 navtool_router_calculate_route_streaming_v8(
    const navtool_router_request_v8* in, navtool_router_progress_callback_v8 callback, void* progress_data,
    navtool_router_segment_eligibility_callback_v1 eligible, void* eligibility_data, char** text, size_t* length) {
    return protect([&]() -> navtool_router_status_v1 {
        if (!json_outputs(text, length)) return fail(NAVTOOL_ROUTER_STATUS_INVALID_ARGUMENT_V1, "route JSON outputs required");
        sailroute::RouteRequest request;
        sailroute::RoutingEnvironment environment;
        auto status = prepare_request(in, request, environment, eligible, eligibility_data);
        if (status) return status;
        const sailroute::Router router{in->forecast->weather, in->polar->polar, std::move(environment)};
        sailroute::RoutingViewControlCallback progress;
        if (callback) progress = [callback, progress_data](const sailroute::RoutingProgressView& p) { return deliver_progress(p, callback, progress_data); };
        auto route = router.optimize_view(request, progress);
        if (!route) return error_v8(route.error());
        return copy_route_json(route.value(), text, length);
    });
}

navtool_router_status_v1 navtool_router_evaluate_actions_v8(
    const navtool_router_request_v8* in, const navtool_router_action_v8* actions, uint64_t count,
    navtool_router_segment_eligibility_callback_v1 eligible, void* eligibility_data, char** text, size_t* length) {
    return protect([&]() -> navtool_router_status_v1 {
        if (!json_outputs(text, length)) return fail(NAVTOOL_ROUTER_STATUS_INVALID_ARGUMENT_V1, "replay JSON outputs required");
        if (!actions || !count || count > 10000) return fail(NAVTOOL_ROUTER_STATUS_INVALID_ARGUMENT_V1, "replay requires 1..10000 explicit timed headings");
        sailroute::RouteRequest request;
        sailroute::RoutingEnvironment environment;
        auto status = prepare_request(in, request, environment, eligible, eligibility_data);
        if (status) return status;
        std::vector<sailroute::SailingAction> policy;
        int64_t total = 0;
        const auto maximum = request.options.maximum_route_duration.count() * 3600;
        for (uint64_t i = 0; i < count; ++i) {
            if (!nonnegative(actions[i].heading_degrees) || actions[i].heading_degrees >= 360 ||
                actions[i].duration_seconds <= 0 || actions[i].duration_seconds > maximum - total)
                return fail(NAVTOOL_ROUTER_STATUS_INVALID_ARGUMENT_V1, "replay headings must be canonical and total action duration cannot exceed the configured duration");
            total += actions[i].duration_seconds;
            policy.push_back({actions[i].heading_degrees, std::chrono::seconds{actions[i].duration_seconds}});
        }
        const sailroute::Router router{in->forecast->weather, in->polar->polar, std::move(environment)};
        auto result = router.evaluate_actions(request, policy);
        if (!result) return error_v8(result.error());
        return copy_route_json(result.value(), text, length);
    });
}

navtool_router_status_v1 navtool_router_check_planned_hold_v8(
    const navtool_router_exclusion_settings_v7* exclusions, navtool_router_coordinate_v1 point, int64_t arrival, int64_t departure,
    uint8_t* conflict, uint64_t* tests, char** zone, size_t* length) {
    return protect([&]() -> navtool_router_status_v1 {
        if (conflict) *conflict = 0;
        if (tests) *tests = 0;
        if (!json_outputs(zone, length) || !conflict || !tests || !exclusions || exclusions->configured != 1 ||
            !valid_coordinate(point.latitude_degrees, point.longitude_degrees) || arrival >= departure ||
            arrival < -62135596800LL || departure > 253370764800LL || !valid_exclusion_text(*exclusions))
            return fail(NAVTOOL_ROUTER_STATUS_INVALID_ARGUMENT_V1, "hold requires configured exclusions, valid UTF-8, canonical position and increasing supported UTC times");
        sailroute::ExclusionSettings settings;
        auto status = apply_exclusion_settings_v7(*exclusions, settings);
        if (status) return status;
        const sailroute::Coordinate c{point.latitude_degrees, point.longitude_degrees};
        const auto check = settings.zones->intersects_segment(c, from_epoch(arrival), c, from_epoch(departure), settings.boundary_policy);
        *conflict = check.violated;
        *tests = check.geometry_tests;
        return copy_utf8(std::string{check.zone_identifier}, zone, length);
    });
}
} // extern "C"
