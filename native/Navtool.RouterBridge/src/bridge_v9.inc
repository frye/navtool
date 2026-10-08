#include "sailroute/coastal_pruning.hpp"

namespace {
navtool_router_coastal_diagnostics_v9 copy_coastal(
    const sailroute::CoastalPruningDiagnostics& audit, uint64_t application_work) {
    navtool_router_coastal_diagnostics_v9 out{};
    out.struct_size = sizeof(out);
    out.mode = static_cast<int32_t>(audit.effective);
    out.requested_mode = static_cast<int32_t>(audit.requested);
    out.status_utf8 = audit.bound_status.c_str();
    out.unavailable_reason_utf8 = audit.speed_upper_knots ? nullptr : audit.bound_status.c_str();
    out.skipped_parents = audit.parent_expansions_skipped;
    out.disconnected_candidates = audit.candidates_disconnected;
    out.horizon_candidates = audit.candidates_horizon;
    out.incumbent_candidates = audit.candidates_incumbent;
    out.bound_unavailable = audit.bound_unavailable;
    out.seed_evaluations = audit.seed_transition_evaluations;
    out.topology_work = audit.topology_work + application_work;
    out.has_incumbent_arrival = audit.incumbent_arrival.has_value();
    if (audit.incumbent_arrival) out.incumbent_arrival_epoch_seconds = to_epoch(*audit.incumbent_arrival);
    out.source_identity_utf8 = audit.source_identity.c_str();
    out.domain_identity_utf8 = audit.domain_identity.c_str();
    out.seed_status_utf8 = audit.seed_status.c_str();
    out.speed_upper_knots = audit.speed_upper_knots.value_or(0);
    out.has_speed_upper = audit.speed_upper_knots.has_value();
    out.topology_caps = audit.topology_caps;
    out.numerical_margin_nautical_miles = audit.topology_numerical_margin_nautical_miles;
    out.clearance_nautical_miles = audit.clearance_nautical_miles;
    return out;
}

struct CoastalProgressDelivery {
    navtool_router_progress_callback_v9 callback;
    void* user_data;
    const sailroute::CoastalPruningDiagnostics* audit;
    uint64_t application_work;
};

uint8_t deliver_coastal_base(const navtool_router_progress_v8* base, void* data) {
    const auto& delivery = *static_cast<CoastalProgressDelivery*>(data);
    navtool_router_progress_v9 out{};
    out.struct_size = sizeof(out);
    out.base = *base;
    out.coastal = copy_coastal(*delivery.audit, delivery.application_work);
    return delivery.callback(&out, delivery.user_data);
}
} // namespace

extern "C" {
navtool_router_status_v1 navtool_router_calculate_route_streaming_v9(
    const navtool_router_request_v9* in, navtool_router_progress_callback_v9 callback, void* progress_data,
    navtool_router_segment_eligibility_callback_v1 eligible, void* eligibility_data,
    navtool_router_continue_callback_v9 should_continue, void* control_data, char** text, size_t* length) {
    return protect([&]() -> navtool_router_status_v1 {
        if (!json_outputs(text, length))
            return fail(NAVTOOL_ROUTER_STATUS_INVALID_ARGUMENT_V1, "route JSON outputs required");
        if (!in || in->struct_size != sizeof(*in) || in->coastal_pruning_mode != 1 ||
            !in->topology || in->maximum_seed_transitions == 0 || in->maximum_seed_transitions > 10000)
            return fail(NAVTOOL_ROUTER_STATUS_INVALID_ARGUMENT_V1, "ABI 9 requires conservative mode, topology and bounded seed work");
        sailroute::RouteRequest request;
        sailroute::RoutingEnvironment environment;
        auto status = prepare_request(&in->base, request, environment, eligible, eligibility_data);
        if (status) return status;
        if (request.options.solver != sailroute::RoutingSolver::isochrone_beam)
            return fail(NAVTOOL_ROUTER_STATUS_INVALID_ARGUMENT_V1, "coastal pruning supports only the isochrone beam solver");
        const auto& t = *in->topology;
        if (t.struct_size != sizeof(t) || t.reserved ||
            !utf8_valid(t.source_identity_utf8) || !*t.source_identity_utf8 ||
            !utf8_valid(t.domain_identity_utf8) || !*t.domain_identity_utf8 ||
            !valid_coordinate(t.south, t.west) || !valid_coordinate(t.north, t.east) || t.south >= t.north ||
            t.cap_count > 1024 || t.probe_count > 4096 || t.application_geometry_work > 100000 ||
            (t.cap_count && !t.caps) || (t.probe_count && !t.probes))
            return fail(NAVTOOL_ROUTER_STATUS_INVALID_ARGUMENT_V1, "invalid coastal topology identity, domain or resource limits");
        if (!environment.land.configured() && !eligible)
            return fail(NAVTOOL_ROUTER_STATUS_INVALID_ARGUMENT_V1, "certified coastal caps require a land enforcement callback");
        if (environment.land.configured() && t.cap_count)
            return fail(NAVTOOL_ROUTER_STATUS_INVALID_ARGUMENT_V1, "native land cannot be combined with application coastal caps");
        const auto cancelled = [should_continue, control_data] {
            return should_continue && !should_continue(control_data);
        };
        if (cancelled()) return fail(NAVTOOL_ROUTER_STATUS_CANCELLED_V8, "coastal preparation cancelled");
        sailroute::CoastalTopologyOptions preparation;
        preparation.source_identity = t.source_identity_utf8;
        preparation.domain_identity = t.domain_identity_utf8;
        preparation.domain = {t.south, t.north, t.west, t.east, {}, {}, t.west == -180 && t.east == 180};
        preparation.clearance_nautical_miles = environment.land.configured() ? environment.land.clearance_nautical_miles : 0;
        preparation.numerical_margin_nautical_miles = .001;
        preparation.maximum_caps = 1024;
        preparation.maximum_work = 1000000;
        preparation.cancelled = cancelled;
        std::vector<sailroute::Coordinate> probes;
        probes.reserve(static_cast<size_t>(t.probe_count));
        for (uint64_t i = 0; i < t.probe_count; ++i) {
            const auto& p = t.probes[i];
            if (!valid_coordinate(p.latitude_degrees, p.longitude_degrees))
                return fail(NAVTOOL_ROUTER_STATUS_INVALID_ARGUMENT_V1, "invalid coastal probe coordinate");
            probes.push_back({p.latitude_degrees, p.longitude_degrees});
        }
        std::vector<sailroute::CoastalTopology::Cap> caps;
        caps.reserve(static_cast<size_t>(t.cap_count));
        for (uint64_t i = 0; i < t.cap_count; ++i) {
            const auto& c = t.caps[i];
            if (!valid_coordinate(c.center.latitude_degrees, c.center.longitude_degrees) ||
                !positive(c.radius_nautical_miles))
                return fail(NAVTOOL_ROUTER_STATUS_INVALID_ARGUMENT_V1, "invalid certified coastal cap");
            caps.push_back({{c.center.latitude_degrees, c.center.longitude_degrees}, c.radius_nautical_miles});
        }
        auto topology = environment.land.configured()
            ? sailroute::CoastalTopology::from_landmask(*environment.land.landmask, probes, preparation)
            : sailroute::CoastalTopology::from_certified_caps(std::move(caps), preparation);
        if (!topology) return error_v8(topology.error());
        auto& options = request.options.coastal_pruning;
        options.mode = sailroute::CoastalPruningMode::conservative;
        options.topology = std::move(topology.value());
        options.source_identity = preparation.source_identity;
        options.domain_identity = preparation.domain_identity;
        options.clearance_nautical_miles = preparation.clearance_nautical_miles;
        options.maximum_seed_transitions = static_cast<size_t>(in->maximum_seed_transitions);
        options.cancelled = cancelled;
        request.options.progress.destination_front.mode = sailroute::DestinationFrontMode::retained_frontier;
        sailroute::RoutingViewControlCallback progress;
        if (callback) progress = [&](const sailroute::RoutingProgressView& p) {
            if (!p.diagnostics.coastal_pruning)
                throw std::runtime_error("enabled coastal progress is missing native audit");
            if (!p.provisional_route.empty() && !p.post_proof_retained_front)
                throw std::runtime_error("coastal main progress is not a post-proof retained frontier");
            CoastalProgressDelivery delivery{callback, progress_data, &*p.diagnostics.coastal_pruning, t.application_geometry_work};
            return deliver_progress(p, deliver_coastal_base, &delivery);
        };
        const sailroute::Router router{in->base.forecast->weather, in->base.polar->polar, std::move(environment)};
        auto route = router.optimize_view(request, progress);
        if (!route) return error_v8(route.error());
        if (!route.value().diagnostics.coastal_pruning)
            return fail(NAVTOOL_ROUTER_STATUS_OUTPUT_ERROR_V1, "enabled coastal route is missing native audit");
        route.value().diagnostics.coastal_pruning->topology_work += static_cast<size_t>(t.application_geometry_work);
        return copy_route_json(route.value(), text, length);
    });
}
} // extern "C"
