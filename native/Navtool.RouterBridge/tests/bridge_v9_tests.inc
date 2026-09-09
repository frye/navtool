static_assert(sizeof(navtool_router_coastal_diagnostics_v9) == 160);
static_assert(sizeof(navtool_router_progress_v9) == 400);
static_assert(sizeof(navtool_router_coastal_topology_v9) == 96);
static_assert(sizeof(navtool_router_request_v9) == 136);
static_assert(offsetof(navtool_router_progress_v9, base) == 8);

uint8_t coastal_land(const navtool_router_coordinate_v1* from, const navtool_router_coordinate_v1* to, void* data) {
    const auto& land = *static_cast<const sailroute::ExclusionZoneSet*>(data);
    return !land.intersects_segment({from->latitude_degrees, from->longitude_degrees}, sailroute::TimePoint{},
        {to->latitude_degrees, to->longitude_degrees}, sailroute::TimePoint{},
        sailroute::ExclusionBoundaryPolicy::boundary_excluded).violated;
}

struct CoastalCapture { Capture base; uint64_t skipped{}, rejected{}; };
uint8_t coastal_progress(const navtool_router_progress_v9* value, void* data) {
    auto& capture = *static_cast<CoastalCapture*>(data);
    check(value && value->struct_size == sizeof(*value) && value->coastal.struct_size == sizeof(value->coastal),
        "invalid coastal progress layout");
    const auto& a = value->coastal;
    check(a.mode == 1 && a.requested_mode == 1 && a.status_utf8 && a.source_identity_utf8 && a.domain_identity_utf8,
        "missing coastal progress provenance");
    const auto rejected = a.disconnected_candidates + a.horizon_candidates + a.incumbent_candidates;
    check(a.skipped_parents >= capture.skipped && rejected >= capture.rejected, "nonmonotonic coastal counters");
    capture.skipped = a.skipped_parents;
    capture.rejected = rejected;
    return progress(&value->base, &capture.base);
}

void test_coastal_v9() {
    const auto rectangle = [](double south, double north, double west, double east) {
        sailroute::ExclusionRing ring;
        const std::array<sailroute::Coordinate, 4> corners{{{south,west},{south,east},{north,east},{north,west}}};
        for (size_t edge = 0; edge < corners.size(); ++edge)
        for (int step = 0; step < 20; ++step) {
            const auto a = corners[edge], b = corners[(edge + 1) % corners.size()];
            const double fraction = step / 20.0;
            ring.vertices.push_back({a.latitude_degrees + fraction * (b.latitude_degrees - a.latitude_degrees),
                a.longitude_degrees + fraction * (b.longitude_degrees - a.longitude_degrees)});
        }
        return ring;
    };
    auto hole = rectangle(-10, 10, -55, 55);
    hole.vertices.insert(hole.vertices.begin(), 400, hole.vertices.front());
    sailroute::CoastalTopologyOptions proof_options;
    proof_options.source_identity = "duplicate-hole-regression";
    proof_options.domain_identity = "duplicate-hole-domain";
    proof_options.domain = {-30,30,-70,70,{},{},false};
    const std::array<sailroute::Coordinate, 1> probes{{{0,50}}};
    auto proof = sailroute::CoastalTopology::from_polygons(
        {{rectangle(-20,20,-65,65), {hole}}}, probes, proof_options);
    check(bool(proof), "duplicate-hole proof input was rejected instead of normalized");
    check(proof.value()->cap_count() == 0, "duplicate vertices turned navigable hole into a forbidden cap");
    check(proof.value()->optimistic_distance_nautical_miles({-9,50},{9,50},0) <=
        3440.065 * 18 * std::numbers::pi / 180 + .001, "hole proof exceeded legal meridian distance");
    make_wind(fixtures / "coastal-region.grib", false, false, false, true);
    check(navtool_router_bridge_capabilities_v1() & NAVTOOL_ROUTER_CAPABILITY_COASTAL_PRUNING_V9,
        "missing coastal capability");
    Forecast forecast;
    auto fo = sized<navtool_router_forecast_options_v8>();
    fo.flags = 2; fo.maximum_interpolation_gap_seconds = 21600;
    ok(navtool_router_forecast_load_v8((fixtures / "constant.grib").string().c_str(), &fo, &forecast.p), "coastal forecast");
    Polar polar;
    load_polar(polar, "coastal.csv", "TWA/TWS,0,10,50\n0,8,8,8\n45,8,8,8\n90,8,8,8\n135,8,8,8\n180,8,8,8\n");
    auto o = defaults();
    o.heading_step_degrees = 15;
    o.maximum_route_duration_hours = 12;
    o.arrival_radius_nautical_miles = .25;
    auto base = request(forecast, polar, o);
    base.destination = {0, .8};
    sailroute::ExclusionZone zone;
    zone.identifier = "northern-land";
    zone.polygons.push_back({{{{.25,.1},{.25,.7},{.75,.7},{.75,.1}}},{}});
    auto land = sailroute::ExclusionZoneSet::create({zone},{"synthetic-coast","test","1"});
    check(bool(land), "invalid coastal fixture geometry");
    navtool_router_coastal_cap_v9 cap{{.5,.4}, 10};
    auto topology = sized<navtool_router_coastal_topology_v9>();
    topology.south = -1.5; topology.north = 1.5; topology.west = -.5; topology.east = 2.5;
    topology.source_identity_utf8 = "synthetic-coast-v1";
    topology.domain_identity_utf8 = "coastal-fixture-domain-v1";
    topology.caps = &cap; topology.cap_count = 1;
    auto r = sized<navtool_router_request_v9>();
    r.coastal_pruning_mode = 1; r.base = base; r.topology = &topology; r.maximum_seed_transitions = 512;
    Text off;
    ok(navtool_router_calculate_route_streaming_v8(&base, nullptr, nullptr, coastal_land, &land.value(), &off.p, &off.n), "coastal Off");
    Text on;
    CoastalCapture capture;
    ok(navtool_router_calculate_route_streaming_v9(&r, coastal_progress, &capture, coastal_land, &land.value(),
        nullptr, nullptr, &on.p, &on.n), "coastal On");
    check(field(on.str(), "completion") == "destination_reached" && elapsed(on.str()) <= elapsed(off.str()) + 2,
        "coastal route did not retain arrival quality");
    check(capture.base.count && capture.rejected + capture.skipped > 0, "coastal search did not report real pruning");
    check(on.str().find("\"coastalPruning\"") != std::string::npos &&
        on.str().find("\"sourceIdentity\":\"synthetic-coast-v1\"") != std::string::npos, "missing final coastal audit");
    save("coastal-off.json", off.str()); save("coastal-on.json", on.str());
    Text cancelled;
    check(navtool_router_calculate_route_streaming_v9(&r, nullptr, nullptr, coastal_land, &land.value(),
        [](void*) -> uint8_t { return 0; }, nullptr, &cancelled.p, &cancelled.n) == NAVTOOL_ROUTER_STATUS_CANCELLED_V8 &&
        !cancelled.p, "coastal preparation cancellation promoted geometry");
    auto invalid = r;
    invalid.struct_size--;
    check(navtool_router_calculate_route_streaming_v9(&invalid, nullptr, nullptr, coastal_land, &land.value(),
        nullptr, nullptr, &cancelled.p, &cancelled.n) == NAVTOOL_ROUTER_STATUS_INVALID_ARGUMENT_V1, "accepted wrong ABI9 size");
    o.common.solver = 1;
    check(navtool_router_calculate_route_streaming_v9(&r, nullptr, nullptr, coastal_land, &land.value(),
        nullptr, nullptr, &cancelled.p, &cancelled.n) != 0, "coastal mode silently accepted lattice");
}
