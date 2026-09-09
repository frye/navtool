#include "navtool_router_bridge.h"
#include "sailroute/sailroute.hpp"
#include "sailroute/land_data.hpp"
#include "sailroute/coastal_pruning.hpp"
#include <eccodes.h>
#include <array>
#include <chrono>
#include <cmath>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <limits>
#include <memory>
#include <numbers>
#include <regex>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

namespace {
static_assert(sizeof(navtool_router_options_v8) == 552);
static_assert(offsetof(navtool_router_options_v8, common) == 16);
static_assert(offsetof(navtool_router_options_v8, intervals) == 296);
static_assert(sizeof(navtool_router_request_v8) == 112);
static_assert(sizeof(navtool_router_route_point_v8) == 152);
static_assert(sizeof(navtool_router_progress_v8) == 232);
static_assert(offsetof(navtool_router_progress_v8, progress) == 8);
static_assert(offsetof(navtool_router_progress_v8, audited_route_points) == 192);
static_assert(sizeof(navtool_router_forecast_metadata_v8) == 104);
static_assert(sizeof(navtool_router_land_options_v8) == 80);
static_assert(sizeof(navtool_router_land_estimate_v8) == 88);

void check(bool valid, const std::string& message) { if (!valid) throw std::runtime_error(message); }
void ok(int32_t status, const char* name) { check(status == 0, std::string{name} + ": " + navtool_router_last_error_v1()); }
void codes(int result) { check(result == CODES_SUCCESS, codes_get_error_message(result)); }
template<class T> T sized() { T value{}; value.struct_size = sizeof(T); return value; }
struct Polar {
    navtool_router_polar_v8* p{};
    ~Polar() { navtool_router_polar_destroy_v8(&p); }
};
struct Forecast {
    navtool_router_forecast_v1* p{};
    ~Forecast() { navtool_router_forecast_destroy_v1(&p); }
};
struct Land {
    navtool_router_land_v8* p{};
    ~Land() { navtool_router_land_destroy_v8(&p); }
};
struct Text {
    char* p{};
    size_t n{};
    ~Text() { navtool_router_bridge_free_v1(p); }
    std::string str() const { return p ? std::string{p, n} : ""; }
};
const std::filesystem::path fixtures = std::filesystem::current_path() / "fixtures-v8";

std::string field(const std::string& json, const std::string& key) {
    std::smatch result;
    check(std::regex_search(json, result, std::regex{"\"" + key + "\":\"([^\"]*)\""}), "missing JSON field " + key);
    return result[1];
}
int64_t elapsed(const std::string& json) {
    auto start = sailroute::parse_utc_time(field(json, "departure\":\\{\"time"));
    auto end = sailroute::parse_utc_time(field(json, "arrival\":\\{\"time"));
    check(start && end, "invalid serialized route times");
    return (end.value() - start.value()).count();
}
void save(const std::string& name, const std::string& json) {
    std::ofstream file(fixtures / name); file << json;
    check(static_cast<bool>(file), "cannot preserve native fixture");
}

std::vector<sailroute::RoutePoint> points_from_fixture(const std::string& json) {
    const std::regex pattern{R"regex(\{"time":"([^"]+)","position":\{"latitude":([-+0-9.eE]+),"longitude":([-+0-9.eE]+)\},"headingDegrees":([-+0-9.eE]+),"boatSpeedKnots":([-+0-9.eE]+))regex"};
    std::vector<sailroute::RoutePoint> points;
    for (std::sregex_iterator it(json.begin(),json.end(),pattern), end; it != end; ++it) {
        const auto& m = *it;
        auto time = sailroute::parse_utc_time(m[1].str());
        check(bool(time), "fixture point time invalid");
        sailroute::RoutePoint p{}; p.time = time.value();
        p.position = {std::stod(m[2]),std::stod(m[3])}; p.heading_degrees = std::stod(m[4]); p.boat_speed_knots = std::stod(m[5]);
        points.push_back(p);
    }
    check(!points.empty(), "fixture points missing");
    return points;
}

double distance_nm(sailroute::Coordinate a, navtool_router_coordinate_v1 b) {
    constexpr double rad = std::numbers::pi / 180;
    const double x = std::sin((b.latitude_degrees-a.latitude_degrees)*rad/2);
    const double y = std::sin((b.longitude_degrees-a.longitude_degrees)*rad/2);
    return 6880.13 * std::asin(std::min(1.,std::sqrt(x*x+std::cos(a.latitude_degrees*rad)*std::cos(b.latitude_degrees*rad)*y*y)));
}

void make_wind(const std::filesystem::path& path, bool mirrored = false, bool strategic = false, bool one_time = false,
    bool coastal_region = false) {
    bool first = true;
    const auto hours = one_time ? std::vector<long>{0} : (strategic ? std::vector<long>{0,5,6,18} : std::vector<long>{0,1,2,3,6,9,12,18});
    for (long hour : hours) for (const char* component : {"10u", "10v"}) {
        std::unique_ptr<codes_handle, decltype(&codes_handle_delete)> h{codes_grib_handle_new_from_samples(nullptr, "regular_ll_sfc_grib2"), codes_handle_delete};
        check(bool(h), "cannot create deterministic GRIB");
        const long count = strategic ? 121 : 13;
        const double spacing = 3.0 / static_cast<double>(count - 1);
        const double north = coastal_region ? 58 : 1.5;
        const double south = coastal_region ? 40 : -1.5;
        const double west = coastal_region ? -138 : -.5;
        const double east = coastal_region ? -108 : 2.5;
        codes(codes_set_long(h.get(), "Ni", count)); codes(codes_set_long(h.get(), "Nj", count));
        codes(codes_set_long(h.get(), "iScansNegatively", 0)); codes(codes_set_long(h.get(), "jScansPositively", 0));
        codes(codes_set_double(h.get(), "latitudeOfFirstGridPointInDegrees", north));
        codes(codes_set_double(h.get(), "latitudeOfLastGridPointInDegrees", south));
        codes(codes_set_double(h.get(), "longitudeOfFirstGridPointInDegrees", west));
        codes(codes_set_double(h.get(), "longitudeOfLastGridPointInDegrees", east));
        codes(codes_set_double(h.get(), "iDirectionIncrementInDegrees", (east - west) / (count - 1)));
        codes(codes_set_double(h.get(), "jDirectionIncrementInDegrees", (north - south) / (count - 1)));
        if (coastal_region) codes(codes_set_long(h.get(), "centre", 7));
        codes(codes_set_long(h.get(), "dataDate", 20260714)); codes(codes_set_long(h.get(), "dataTime", 0));
        codes(codes_set_long(h.get(), "forecastTime", hour));
        size_t len = std::strlen(component); codes(codes_set_string(h.get(), "shortName", component, &len));
        codes(codes_set_long(h.get(), "level", 10));
        std::vector<double> values;
        for (long row = 0; row < count; ++row) for (long column = 0; column < count; ++column) {
            const double lat = (mirrored ? -1 : 1) * (1.5 - static_cast<double>(row) * spacing);
            const double lon = -.5 + static_cast<double>(column) * spacing;
            const double knots = strategic ? (hour >= 6 && lat <= -.25 + std::max(0., lon - .30) + 1e-9 ? 32 : 8) : 10;
            values.push_back(component[2] == 'u' ? -knots * 1852 / 3600 : 0);
        }
        codes(codes_set_double_array(h.get(), "values", values.data(), values.size()));
        codes(codes_write_message(h.get(), path.string().c_str(), first ? "w" : "a")); first = false;
    }
}

void load_polar(Polar& p, const std::string& name, const std::string& contents, int32_t format = 1) {
    auto path = fixtures / name;
    { std::ofstream file(path); file << contents; }
    auto o = sized<navtool_router_polar_options_v8>(); o.format = format;
    ok(navtool_router_polar_load_v8(path.string().c_str(), &o, &p.p), "load explicit polar");
}

navtool_router_options_v8 defaults(int quality = 1) {
    auto o = sized<navtool_router_options_v8>();
    ok(navtool_router_quality_defaults_v8(quality, &o), "native defaults");
    return o;
}
navtool_router_request_v8 request(Forecast& forecast, Polar& polar, navtool_router_options_v8& o) {
    auto r = sized<navtool_router_request_v8>();
    r.flags = 1; r.forecast = forecast.p; r.polar = polar.p; r.options = &o;
    r.start = {0,0}; r.destination = {0, .2};
    r.departure_utc_epoch_seconds = sailroute::parse_utc_time("2026-07-14T00:00:00Z").value().time_since_epoch().count();
    return r;
}
struct Capture {
    std::thread::id caller = std::this_thread::get_id();
    std::vector<navtool_router_route_point_v8> copied;
    uint64_t count{}, evaluations{}, pruned{}, misses{};
    bool current{}, lattice{}, cancel{};
};
uint8_t progress(const navtool_router_progress_v8* p, void* data) {
    auto& c = *static_cast<Capture*>(data);
    check(p && p->struct_size == sizeof(*p) && c.caller == std::this_thread::get_id(), "progress is not synchronous or sized");
    check(p->audited_route_point_count == p->progress.provisional_route_point_count, "audit point count mismatch");
    check(p->eligibility_evaluations >= c.evaluations && p->pruned_candidates >= c.pruned && p->future_probe_misses >= c.misses, "nonmonotonic audit counters");
    c.evaluations = p->eligibility_evaluations; c.pruned = p->pruned_candidates; c.misses = p->future_probe_misses;
    c.copied.assign(p->audited_route_points, p->audited_route_points + p->audited_route_point_count);
    for (const auto& point : c.copied) if (point.flags & 2) {
        c.current = true;
        check(point.flags & 1, "current audit missing environment");
        check(std::isfinite(point.polar_wind_speed_knots), "invalid polar-wind audit");
    }
    c.lattice = c.lattice || p->progress.search_point_count > 0;
    if (p->progress.solver == 1) check(p->progress.contour_point_count == 0 && p->progress.front_point_count == 0, "lattice sent beam fronts");
    ++c.count; return c.cancel ? 0 : 1;
}
std::string calculate(const navtool_router_request_v8& r, Capture* capture = nullptr,
    navtool_router_segment_eligibility_callback_v1 eligible = nullptr) {
    Text out;
    ok(navtool_router_calculate_route_streaming_v8(&r, capture ? progress : nullptr, capture, eligible, nullptr, &out.p, &out.n), "configured calculate");
    check(out.str().find("\"schema\":\"route_result_v2\"") != std::string::npos, "final output not route_result_v2");
    return out.str();
}
uint8_t east_only(const navtool_router_coordinate_v1* from, const navtool_router_coordinate_v1* to, void*) {
    return to->longitude_degrees >= from->longitude_degrees;
}

void test_defaults_and_validation() {
    Text build; ok(navtool_router_build_info_v8(&build.p, &build.n), "build info");
    check(build.str().find("\"ensemble_enabled\":false") != std::string::npos, "ensemble must be disabled");
    check(build.str().find("\"land_data_enabled\":true") != std::string::npos, "GSHHG must be enabled");
    save("build-info.json", build.str());
    for (int quality = 0; quality < 3; ++quality) {
        const auto o = defaults(quality);
        const auto upstream = sailroute::routing_options_for_quality(static_cast<sailroute::RoutingQuality>(quality));
        check(o.time_step_minutes == upstream.time_step.count() && o.heading_step_degrees == upstream.heading_step_degrees &&
            o.spatial_bucket_nautical_miles == upstream.spatial_bucket_nautical_miles && o.max_nodes_per_bucket == upstream.max_nodes_per_bucket &&
            o.use_routing_intervals == upstream.use_routing_intervals && o.strategic_retention == upstream.strategic_retention &&
            o.common.lattice_refinement_levels == upstream.lattice.refinement_levels && o.maximum_generated_candidates == upstream.maximum_generated_candidates &&
            o.maximum_retained_nodes == upstream.maximum_retained_nodes && o.maximum_integration_step_minutes == upstream.maximum_integration_step.count(),
            "native preset fidelity lost");
        check(o.common.above_polar_range == 1 && o.common.polar_angle_interpolation == 0 && o.boat_speed_factor == 1, "native physical defaults changed");
        auto copy = sized<navtool_router_options_v8>(); ok(navtool_router_resolve_options_v8(&o, &copy), "resolve native defaults");
        check(std::memcmp(&o, &copy, sizeof(o)) == 0, "full native preset roundtrip lost fields");
    }
    auto o = defaults(); auto out = sized<navtool_router_options_v8>();
    o.override_flags = NAVTOOL_ROUTER_OVERRIDE_BOAT_FACTOR_V8; o.boat_speed_factor = .8; o.heading_step_degrees = 999;
    ok(navtool_router_resolve_options_v8(&o, &out), "only flagged override");
    check(out.boat_speed_factor == .8 && out.heading_step_degrees == defaults().heading_step_degrees, "unflagged option leaked");
    o.override_flags = 1ULL << 63; check(navtool_router_resolve_options_v8(&o, &out) == 1, "unknown flags accepted");
    o = defaults(); o.struct_size--; check(navtool_router_resolve_options_v8(&o, &out) == 1, "wrong layout accepted");
    o = defaults(); o.common.solver = 7; check(navtool_router_resolve_options_v8(&o, &out) == 1, "invalid enum accepted");
    o = defaults(); o.maximum_integration_step_minutes = INT64_MAX; check(navtool_router_resolve_options_v8(&o, &out) == 1, "chrono overflow accepted");
    o = defaults(); o.maximum_generated_candidates = 0; check(navtool_router_resolve_options_v8(&o, &out) == 1, "zero budget accepted");
    o = defaults(); o.boat_speed_factor = std::numeric_limits<double>::quiet_NaN(); check(navtool_router_resolve_options_v8(&o, &out) == 1, "NaN factor accepted");
    o = defaults(); o.interval_count = 17; check(navtool_router_resolve_options_v8(&o, &out) == 1, "interval overflow accepted");
    o = defaults(); o.use_routing_intervals = 0; o.time_step_minutes = 1; check(navtool_router_resolve_options_v8(&o, &out) == 1, "subminimum native route interval accepted");
    o = defaults(); o.intervals[1].until_elapsed_minutes = 1; check(navtool_router_resolve_options_v8(&o, &out) == 1, "unordered interval accepted");
    Polar invalid;
    auto po = sized<navtool_router_polar_options_v8>();
    const char malformed[] = {'x', char(0xc0), char(0xaf), 0};
    check(navtool_router_polar_load_v8(malformed, &po, &invalid.p) == 1 && !invalid.p, "invalid UTF-8 accepted");
    { std::ofstream f(fixtures / "invalid.pol"); f << "not a polar"; }
    check(navtool_router_polar_load_v8((fixtures / "invalid.pol").string().c_str(), &po, &invalid.p) == 14 && !invalid.p, "invalid polar not classified");
    check(navtool_router_polar_load_v8((fixtures / "absent.pol").string().c_str(), &po, &invalid.p) == 3, "missing polar not file error");
    Polar expedition;
    load_polar(expedition, "expedition.pol", "8 45 6 90 8 135 6\n16 45 7 90 10 135 7\n", 2);
    Text metadata; ok(navtool_router_polar_metadata_v8(expedition.p, &metadata.p, &metadata.n), "polar metadata");
    check(metadata.str().find("\"requested_format\":2") != std::string::npos && metadata.str().find("\"resolved_format\":null") != std::string::npos, "resolved format invented");
    ok(navtool_router_polar_destroy_v8(&expedition.p), "destroy polar");
    ok(navtool_router_polar_destroy_v8(&expedition.p), "destroy polar twice");
}

void test_polar_number_parsing() {
    const auto path = fixtures / "numeric-polar.csv";
    const auto write_polar = [&](const std::string& token) {
        std::ofstream file(path);
        file << "TWA/TWS,10,20\n45,6,7\n90," << token << ",8\n135,6,7\n";
        check(static_cast<bool>(file), "cannot write numeric polar");
    };
    struct NumericCase { const char* token; double expected; };
    for (const auto& sample : {
            NumericCase{"6.5", 6.5}, NumericCase{"\"+6.5e0\"", 6.5},
            NumericCase{"1e+1", 10.0}, NumericCase{"1e-20", 1e-20},
            NumericCase{"4.9406564584124654e-324", std::numeric_limits<double>::denorm_min()},
            NumericCase{"2.2250738585072014e-308", std::numeric_limits<double>::min()},
            NumericCase{"-0.0", 0.0}}) {
        write_polar(sample.token);
        auto polar = sailroute::VesselPolar::load(path, {sailroute::PolarFormat::matrix, {}});
        check(bool(polar), std::string{"valid polar number rejected: "} + sample.token);
        check(polar.value().boat_speed_knots(10, 90) == sample.expected,
            std::string{"polar number changed value: "} + sample.token);
    }
    for (const char* token : {"nan", "inf", "-inf", "1e9999", "1e-9999", "6.5x", "0x1p0", "1e", "++6"}) {
        write_polar(token);
        Polar polar;
        auto options = sized<navtool_router_polar_options_v8>(); options.format = 1;
        check(navtool_router_polar_load_v8(path.string().c_str(), &options, &polar.p) == 14 && !polar.p,
            std::string{"invalid polar number accepted: "} + token);
    }
}

void test_forecast() {
    auto path = fixtures / "constant.grib"; make_wind(path);
    auto o = sized<navtool_router_forecast_options_v8>(); o.flags = 2; o.maximum_interpolation_gap_seconds = 21600;
    Forecast f; ok(navtool_router_forecast_load_v8(path.string().c_str(), &o, &f.p), "legal changing cadence");
    auto metadata = sized<navtool_router_forecast_metadata_v8>(); Text source;
    ok(navtool_router_forecast_get_metadata_v8(f.p, &metadata, &source.p, &source.n), "forecast metadata");
    check(metadata.minimum_time_spacing_seconds == 3600 && metadata.maximum_time_spacing_seconds == 21600 && metadata.valid_time_count == 8, "forecast cadence metadata wrong");
    check(metadata.initialization_utc_epoch_seconds == metadata.first_valid_utc_epoch_seconds && metadata.south_latitude_degrees == -1.5, "forecast initialization or bounds wrong");
    uint64_t required; ok(navtool_router_forecast_valid_times_v8(f.p, nullptr, 0, &required), "query valid time capacity");
    check(required == 8, "missing exact valid times"); std::vector<int64_t> times(required);
    ok(navtool_router_forecast_valid_times_v8(f.p, times.data(), times.size(), &required), "read valid times");
    check(times[4] - times[3] == 10800, "cadence transition missing");
    Forecast bad; o.maximum_interpolation_gap_seconds = 10800;
    check(navtool_router_forecast_load_v8(path.string().c_str(), &o, &bad.p) == 6 && !bad.p, "real gap accepted");
    auto one = fixtures / "single.grib"; make_wind(one, false, false, true);
    ok(navtool_router_forecast_load_v8(one.string().c_str(), &o, &bad.p), "single-time forecast");
    auto single = sized<navtool_router_forecast_metadata_v8>(); Text single_source;
    ok(navtool_router_forecast_get_metadata_v8(bad.p, &single, &single_source.p, &single_source.n), "single metadata");
    check((single.flags & 1) == 0 && single.valid_time_count == 1, "single time invented cadence");
}

void test_routes_and_replay() {
    Forecast f; auto fo = sized<navtool_router_forecast_options_v8>();
    ok(navtool_router_forecast_load_v8((fixtures / "constant.grib").string().c_str(), &fo, &f.p), "route forecast");
    Polar fast, slow, demo;
    load_polar(fast, "fast.csv", "TWA/TWS,0,10,50\n0,0,10,10\n45,0,10,10\n90,0,10,10\n135,0,10,10\n180,0,10,10\n");
    load_polar(slow, "slow.csv", "TWA/TWS,0,10,50\n0,0,5,5\n45,0,5,5\n90,0,5,5\n135,0,5,5\n180,0,5,5\n");
    ok(navtool_router_polar_create_demo_v8(&demo.p), "explicit demo");
    auto o = defaults(); o.worker_count = 1; o.use_routing_intervals = 0; o.time_step_minutes = 15; o.common.polar_angle_interpolation = 1;
    auto r = request(f, fast, o); r.destination = {.2, 0};
    Capture captured;
    auto fast_result = calculate(r, &captured);
    check(captured.count > 0 && !captured.copied.empty(), "callback not copied or delivered");
    r.polar = slow.p; auto slow_result = calculate(r);
    check(elapsed(slow_result) > elapsed(fast_result) * 1.9, "explicit boat did not change native physics");
    r.polar = fast.p; o.boat_speed_factor = .5; auto factored = calculate(r);
    check(std::abs(elapsed(factored) - elapsed(slow_result)) < 2, "factor not applied exactly once");
    o.boat_speed_factor = 1; r.polar = demo.p; auto demo_result = calculate(r);
    check(field(demo_result, "polar\":\\{\"source") != field(fast_result, "polar\":\\{\"source"), "demo source lost");
    r.polar = fast.p;
    save("arrived.json", fast_result); save("demo.json", demo_result);
    const navtool_router_action_v8 actions[] = {{0, 7200}};
    Text replay; ok(navtool_router_evaluate_actions_v8(&r, actions, 1, nullptr, nullptr, &replay.p, &replay.n), "explicit timed heading replay");
    check(field(replay.str(), "completion") == "destination_reached" && std::abs(elapsed(replay.str()) - elapsed(fast_result)) < 2, "replay changed known straight heading policy");
    save("replay.json", replay.str());
    navtool_router_environment_v7 environment{};
    environment.currents.mode = 1; environment.currents.uniform_east_knots = 1; environment.currents.metadata = {"uniform", "test current", "1"};
    r.environment = &environment;
    Capture current; auto current_json = calculate(r, &current);
    check(current.current && current_json.find("\"polarWindSpeedKnots\":") != std::string::npos, "current/polar wind audit missing");
    save("current.json", current_json);
    o.common.tack_penalty_seconds = 90; o.common.gybe_penalty_seconds = 60;
    save("maneuver.json", calculate(r));
    r.environment = nullptr; o.common.tack_penalty_seconds = 0; o.common.gybe_penalty_seconds = 0;
    o.common.solver = 1; o.common.lattice_subdivision_level = 3; o.common.lattice_refinement_levels = 0; o.common.lattice_progress_every_n_expansions = 1;
    Capture lattice; save("lattice.json", calculate(r, &lattice));
    check(lattice.count > 0 && lattice.lattice, "lattice search-point progress missing");
    o.common.solver = 0;
    Capture cancel; cancel.cancel = true; Text cancelled;
    check(navtool_router_calculate_route_streaming_v8(&r, progress, &cancel, nullptr, nullptr, &cancelled.p, &cancelled.n) == 16 &&
        !cancelled.p && !cancelled.n && cancel.count, "cancel promoted provisional geometry");
    o.maximum_generated_candidates = 1; Text limited;
    check(navtool_router_calculate_route_streaming_v8(&r, nullptr, nullptr, nullptr, nullptr, &limited.p, &limited.n) == 15 && !limited.p && !limited.n, "resource limit promoted output");
    o.maximum_generated_candidates = defaults().maximum_generated_candidates;
    o.maximum_route_duration_hours = 1; r.destination = {1, 0};
    auto partial = calculate(r); check(field(partial, "completion") == "duration_exhausted", "duration partial missing"); save("duration-partial.json", partial);
    o.maximum_route_duration_hours = 24; r.destination = {1.4, 2.4}; r.polar = slow.p;
    o.time_step_minutes = 60; o.heading_step_degrees = 45; o.spatial_bucket_nautical_miles = 20; o.max_nodes_per_bucket = 1;
    auto forecast_partial = calculate(r); check(field(forecast_partial, "completion") == "forecast_exhausted", "forecast partial missing"); save("forecast-partial.json", forecast_partial);
    r.polar = nullptr; Text missing;
    check(navtool_router_calculate_route_streaming_v8(&r, nullptr, nullptr, nullptr, nullptr, &missing.p, &missing.n) == 1, "implicit demo fallback");
}

void test_holds() {
    std::array<navtool_router_coordinate_v1, 8> vertices{{{-1,-1},{-1,1},{1,1},{1,-1},{-.2,-.2},{-.2,.2},{.2,.2},{.2,-.2}}};
    navtool_router_exclusion_ring_v7 hole{4,4};
    navtool_router_exclusion_polygon_v7 polygon{{0,4},0,0};
    navtool_router_exclusion_zone_v7 zone{"zone", "test", 1, 100, 200, 1, 1, {}, 0, 1};
    navtool_router_exclusion_settings_v7 e{1, {}, 0, &zone, 1, &polygon, 1, &hole, 1, vertices.data(), vertices.size(), {"hold", "test", "1"}};
    const auto hold = [&](int64_t from, int64_t to, bool expected, navtool_router_coordinate_v1 position = {0,0}) {
        uint8_t conflict = 9; uint64_t geometry = 0; Text id;
        ok(navtool_router_check_planned_hold_v8(&e, position, from, to, &conflict, &geometry, &id.p, &id.n), "hold interval");
        check(conflict == expected && (!expected || (id.str() == "zone" && geometry)), "timed hold exclusion semantics wrong");
    };
    hold(50,150,true); hold(150,250,true); hold(50,250,true); hold(200,250,false); hold(50,99,false);
    hold(50,250,true,{-1,-1}); e.boundary_policy = 1; hold(50,250,false,{-1,-1}); e.boundary_policy = 0;
    polygon.hole_count = 1; hold(50,250,false); polygon.hole_count = 0;
    vertices[0] = {-1,179}; vertices[1] = {-1,-179}; vertices[2] = {1,-179}; vertices[3] = {1,179};
    hold(50,250,true,{0,180}); hold(50,250,false,{0,0});
    uint8_t conflict; uint64_t tests; Text invalid;
    check(navtool_router_check_planned_hold_v8(nullptr, {0,0}, 0, 1, &conflict, &tests, &invalid.p, &invalid.n) == 1, "unvalidated exclusions certified");
    check(navtool_router_check_planned_hold_v8(&e, {0,0}, 2, 1, &conflict, &tests, &invalid.p, &invalid.n) == 1, "backward hold accepted");
}

void write_gshhg(const std::filesystem::path& path, int32_t level = 1, bool dateline = false) {
    std::ofstream out(path, std::ios::binary);
    auto word = [&](int32_t value) { uint32_t v = static_cast<uint32_t>(value); for (int shift : {24,16,8,0}) out.put(static_cast<char>((v >> shift) & 255)); };
    // Modern v2.3 native record, one level-1 island entirely away from route.
    const int32_t west = dateline ? 179500000 : 1000000;
    const int32_t east = dateline ? 180500000 : 1100000;
    for (int32_t v : {1,4,level|(15<<8),west,east,1000000,1100000,100,100,-1,-1}) word(v);
    for (auto coordinate : std::array<std::pair<int32_t,int32_t>,4>{{{west,1000000},{east,1000000},{east,1100000},{west,1100000}}}) { word(coordinate.first); word(coordinate.second); }
}

void test_land() {
    auto o = sized<navtool_router_land_options_v8>();
    o.south_latitude_degrees = -.5; o.west_longitude_degrees = -.5; o.north_latitude_degrees = 1.5; o.east_longitude_degrees = 1.5;
    o.resolution_nautical_miles = 10; o.distance_cap_nautical_miles = 30; o.maximum_grid_nodes = 250000; o.maximum_source_points = 10000000; o.maximum_geometry_tests = 100000000;
    auto estimate = sized<navtool_router_land_estimate_v8>();
    ok(navtool_router_land_estimate_v8_fn(&o, &estimate), "GSHHG preview");
    check(estimate.interpolation_error_nautical_miles > o.resolution_nautical_miles, "incorrect half diagonal allowance");
    auto path = fixtures / "island.b"; write_gshhg(path);
    Land land; ok(navtool_router_land_load_gshhg_v8(path.string().c_str(), &o, &land.p), "GSHHG load");
    sailroute::LandDataOptions upstream;
    upstream.bounds = {-.5,-.5,1.5,1.5}; upstream.resolution_nautical_miles = 10; upstream.distance_cap_nautical_miles = 30;
    auto native = sailroute::load_gshhg_landmask(path, upstream); check(bool(native), "upstream land comparison");
    check(native.value().grid().latitude_count == estimate.latitude_count && native.value().grid().longitude_count == estimate.longitude_count &&
        native.value().metadata().interpolation_error_nautical_miles == estimate.interpolation_error_nautical_miles, "preview differs from actual loader");
    Text metadata; ok(navtool_router_land_metadata_v8(land.p, &metadata.p, &metadata.n), "GSHHG metadata"); save("gshhg-metadata.json", metadata.str());
    check(metadata.str().find("\"source_completeness_certified\":false") != std::string::npos, "source completeness invented");
    Forecast f; auto fo = sized<navtool_router_forecast_options_v8>(); ok(navtool_router_forecast_load_v8((fixtures / "constant.grib").string().c_str(), &fo, &f.p), "land forecast");
    Polar p; ok(navtool_router_polar_create_demo_v8(&p.p), "land demo"); auto options = defaults(); options.worker_count = 1;
    auto r = request(f,p,options); r.destination = {.2,0}; r.land = land.p; r.land_maximum_subdivision_depth = 12;
    save("gshhg-route.json", calculate(r));
    Text conflict; check(navtool_router_calculate_route_streaming_v8(&r, nullptr, nullptr, east_only, nullptr, &conflict.p, &conflict.n) == 12, "conflicting land owner accepted");
    navtool_router_environment_v7 environment{}; environment.land.configured = 1; r.environment = &environment;
    check(navtool_router_calculate_route_streaming_v8(&r, nullptr, nullptr, nullptr, nullptr, &conflict.p, &conflict.n) == 12, "SDF and GSHHG combined");
    auto fine = o; fine.resolution_nautical_miles = .05; check(navtool_router_land_estimate_v8_fn(&fine, &estimate) == 15, "GSHHG grid budget ignored");
    auto polar = o; polar.south_latitude_degrees = 84; polar.north_latitude_degrees = 85; polar.distance_cap_nautical_miles = 600;
    check(navtool_router_land_estimate_v8_fn(&polar, &estimate) == 1, "GSHHG polar halo accepted");
    auto cap = o; cap.distance_cap_nautical_miles = 1; check(navtool_router_land_estimate_v8_fn(&cap, &estimate) == 1, "cap smaller than allowance accepted");
    auto raised = o; raised.maximum_grid_nodes++; check(navtool_router_land_estimate_v8_fn(&raised, &estimate) == 1, "raised native budget accepted");
    auto dateline = o; dateline.west_longitude_degrees = 179; dateline.east_longitude_degrees = -179; ok(navtool_router_land_estimate_v8_fn(&dateline, &estimate), "dateline preview");
    const auto dateline_path = fixtures / "dateline.b"; write_gshhg(dateline_path,1,true);
    Land dateline_land; ok(navtool_router_land_load_gshhg_v8(dateline_path.string().c_str(),&dateline,&dateline_land.p),"GSHHG dateline load");
    const auto unsupported_path = fixtures / "unsupported.b"; write_gshhg(unsupported_path,5);
    Land unsupported; check(navtool_router_land_load_gshhg_v8(unsupported_path.string().c_str(),&o,&unsupported.p) == 12 && !unsupported.p,"unsupported GSHHG regional geometry accepted");
    const auto truncated_path = fixtures / "truncated.b"; { std::ofstream file(truncated_path,std::ios::binary); file << "incomplete"; }
    check(navtool_router_land_load_gshhg_v8(truncated_path.string().c_str(),&o,&unsupported.p) == 12 && !unsupported.p,"truncated GSHHG accepted");
    auto source_budget = o; source_budget.maximum_source_points = 3; Land exhausted;
    check(navtool_router_land_load_gshhg_v8(path.string().c_str(), &source_budget, &exhausted.p) == 15 && !exhausted.p, "source budget not enforced");
    ok(navtool_router_land_destroy_v8(&land.p), "land destroy"); ok(navtool_router_land_destroy_v8(&land.p), "land destroy twice");
}

void test_strategic(bool mirrored, bool island, bool diagnostics) {
    const std::string name = std::string{island ? "island-" : "corridor-"} + (mirrored ? "north" : "south");
    const auto path = fixtures / (name + ".grib"); make_wind(path, mirrored, true);
    Forecast f; auto fo = sized<navtool_router_forecast_options_v8>(); fo.flags = 2; fo.maximum_interpolation_gap_seconds = 12 * 3600;
    ok(navtool_router_forecast_load_v8(path.string().c_str(), &fo, &f.p), "strategic forecast");
    Polar polar; load_polar(polar, "strategic.csv", "TWA/TWS,0,8,32,50\n0,0,0,0,0\n44,0,0,0,0\n45,0,6,24,24\n46,0,0,0,0\n134,0,0,0,0\n135,0,6,24,24\n136,0,0,0,0\n180,0,0,0,0\n");
    auto o = defaults(); o.worker_count = 1; o.time_step_minutes = 60; o.use_routing_intervals = 0; o.heading_step_degrees = 45;
    o.common.heading_augmentation = 0; o.arrival_radius_nautical_miles = 2; o.spatial_bucket_nautical_miles = 100; o.max_nodes_per_bucket = 3; o.maximum_route_duration_hours = 18;
    auto r = request(f,polar,o); r.destination = {mirrored ? -.35 : .35, 1};
    navtool_router_coordinate_v1 vertices[] = {{-.04,.12},{-.04,.55},{.04,.55},{.04,.12}};
    navtool_router_exclusion_polygon_v7 polygon{{0,4},0,0};
    navtool_router_exclusion_zone_v7 zone{"synthetic-island","strategic regression",1,0,0,0,0,{},0,1};
    navtool_router_environment_v7 environment{};
    environment.exclusions = {1,{},0,&zone,1,&polygon,1,nullptr,0,vertices,4,{"island","strategic regression","1"}};
    if (island) r.environment = &environment;
    auto start = std::chrono::steady_clock::now();
    Capture captured; auto strategic = calculate(r, &captured, east_only);
    const double wall_ms = std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-start).count();
    o.strategic_retention = 0; o.max_nodes_per_bucket = 1;
    auto greedy = calculate(r, nullptr, east_only);
    check(field(strategic,"completion") == "destination_reached" && field(greedy,"completion") == "destination_reached", "strategic comparison did not arrive");
    check(elapsed(strategic) + 1800 < elapsed(greedy), "future-aware retention lost delayed payoff");
    check(captured.evaluations && captured.pruned, "strategic search audit counters missing");
    const auto selected_points = points_from_fixture(strategic);
    const auto greedy_points = points_from_fixture(greedy);
    const auto at = [](const auto& points, sailroute::TimePoint time) -> const sailroute::RoutePoint& {
        for (const auto& p : points) if (p.time == time) return p;
        throw std::runtime_error("missing controlled hourly boundary");
    };
    unsigned losing = 0, longest = 0;
    for (int hour = 1; hour <= 5; ++hour) {
        const auto time = selected_points.front().time + std::chrono::hours{hour};
        const auto& selected = at(selected_points,time);
        const auto& local = at(greedy_points,time);
        if (distance_nm(selected.position,r.destination) > distance_nm(local.position,r.destination) + 1) longest = std::max(longest,++losing); else losing = 0;
        check(std::abs(selected.boat_speed_knots-6) < .0001 && std::abs(local.boat_speed_knots-6) < .0001, "fixture had an immediate wind advantage");
    }

    check(longest >= 3, "selected route no longer sacrifices early progress");
    if (island) {
        check((mirrored ? -1 : 1)*at(selected_points,selected_points.front().time+std::chrono::hours{1}).position.latitude_degrees < -.04, "island winner did not take losing first tack");
        sailroute::ExclusionZone native_zone; native_zone.identifier = "synthetic-island";
        native_zone.polygons.push_back({{{{-.04,.12},{-.04,.55},{.04,.55},{.04,.12}}},{}});
        auto native_zones = sailroute::ExclusionZoneSet::create({native_zone},{"island","strategic regression","1"});
        check(bool(native_zones), "controlled island invalid");
        for (size_t i = 1; i < selected_points.size(); ++i)
            check(!native_zones.value().intersects_segment(selected_points[i-1].position,selected_points[i-1].time,
                selected_points[i].position,selected_points[i].time,sailroute::ExclusionBoundaryPolicy::boundary_excluded).violated,"strategic selected route crossed island");
    }
    save(name+"-strategic.json", strategic); save(name+"-greedy.json", greedy);
    std::cout << name << " strategic_s=" << elapsed(strategic) << " greedy_s=" << elapsed(greedy) << " wall_ms=" << wall_ms << '\n';
    if (diagnostics) {
        o.strategic_retention = 1; o.max_nodes_per_bucket = 3;
        // Exact controls are known in this controlled fixture: fixed 60-minute
        // actions, 15-minute integration, no maneuvers or heading augmentation.
        // Verify that policy before replay; never apply this to arbitrary routes.
        std::vector<navtool_router_action_v8> policy;
        for (auto time = selected_points.front().time; time < selected_points.back().time; time += std::chrono::hours{1}) {
            const auto end = std::min(time+std::chrono::hours{1},selected_points.back().time);
            std::optional<double> heading;
            for (const auto& point : selected_points) if (point.time > time && point.time <= end) {
                if (!heading) heading = point.heading_degrees;
                check(*heading == point.heading_degrees, "unknown within-action heading policy; refusing replay");
            }
            check(heading.has_value() && (*heading == 45 || *heading == 135), "unknown strategic control heading");
            policy.push_back({*heading,(end-time).count()});
        }
        Text replay; ok(navtool_router_evaluate_actions_v8(&r,policy.data(),policy.size(),east_only,nullptr,&replay.p,&replay.n),"controlled action replay");
        check(field(replay.str(),"completion") == "destination_reached" && std::abs(elapsed(replay.str())-elapsed(strategic)) <= 2,"controlled replay regressed");
        save(name+"-controlled-replay.json",replay.str());
        // Exhaustive ONLY within the declared 9-action {45,135} policy grid.
        // Errors and nonarrivals remain separate, not winning samples.
        int64_t best = INT64_MAX; uint64_t arrivals = 0, errors = 0, partials = 0;
        std::vector<navtool_router_action_v8> reference(9);
        for (uint32_t bits = 0; bits < 512; ++bits) {
            for (uint32_t i = 0; i < reference.size(); ++i) reference[i] = {(bits & (1U<<i)) ? 45. : 135.,3600};
            Text result;
            const auto status = navtool_router_evaluate_actions_v8(&r,reference.data(),reference.size(),east_only,nullptr,&result.p,&result.n);
            if (status) { ++errors; continue; }
            if (field(result.str(),"completion") != "destination_reached") { ++partials; continue; }
            ++arrivals; best = std::min(best,elapsed(result.str()));
        }
        check(arrivals > 0 && std::abs(best-elapsed(strategic)) <= 2,"strategic route differs from bounded discrete action reference");
        std::cout << name << " bounded_reference_s=" << best << " arrivals=" << arrivals << " partials=" << partials << " errors=" << errors << '\n';
    }
}
void test_unicode_asset_paths() {
    const auto directory = fixtures / std::filesystem::path{u8"assets-\u00e9-\u8239"};
    std::filesystem::create_directories(directory);
    const auto polar_path = directory / "boat.csv";
    const auto land_path = directory / "shoreline.b";
    std::filesystem::copy_file(fixtures / "fast.csv", polar_path, std::filesystem::copy_options::overwrite_existing);
    std::filesystem::copy_file(fixtures / "island.b", land_path, std::filesystem::copy_options::overwrite_existing);
    auto utf8 = [](const std::filesystem::path& path) {
        const auto bytes = path.u8string();
        return std::string{reinterpret_cast<const char*>(bytes.data()), bytes.size()};
    };
    const std::string marker = "assets-\xc3\xa9-\xe8\x88\xb9";
    Polar polar;
    auto po = sized<navtool_router_polar_options_v8>();
    po.format = 1;
    ok(navtool_router_polar_load_v8(utf8(polar_path).c_str(), &po, &polar.p), "Unicode polar load");
    Text polar_metadata;
    ok(navtool_router_polar_metadata_v8(polar.p, &polar_metadata.p, &polar_metadata.n), "Unicode polar metadata");
    check(polar_metadata.str().find(marker) != std::string::npos, "polar metadata lost UTF-8 path");
    auto lo = sized<navtool_router_land_options_v8>();
    lo.south_latitude_degrees = -.5; lo.west_longitude_degrees = -.5;
    lo.north_latitude_degrees = 1.5; lo.east_longitude_degrees = 1.5;
    lo.resolution_nautical_miles = 10; lo.distance_cap_nautical_miles = 30;
    lo.maximum_grid_nodes = 250000; lo.maximum_source_points = 10000000; lo.maximum_geometry_tests = 100000000;
    Land land;
    ok(navtool_router_land_load_gshhg_v8(utf8(land_path).c_str(), &lo, &land.p), "Unicode GSHHG load");
    Text land_metadata;
    ok(navtool_router_land_metadata_v8(land.p, &land_metadata.p, &land_metadata.n), "Unicode GSHHG metadata");
    check(land_metadata.str().find(marker) != std::string::npos, "GSHHG metadata lost UTF-8 path");
    Forecast forecast;
    auto fo = sized<navtool_router_forecast_options_v8>();
    ok(navtool_router_forecast_load_v8(utf8(fixtures / "constant.grib").c_str(), &fo, &forecast.p), "Unicode fixture forecast");
    auto options = defaults();
    options.worker_count = 1;
    auto r = request(forecast, polar, options);
    r.land = land.p; r.land_maximum_subdivision_depth = 12;
    check(calculate(r).find(marker) != std::string::npos, "route JSON lost UTF-8 asset path");
    Polar missing;
    check(navtool_router_polar_load_v8(utf8(directory / "missing.pol").c_str(), &po, &missing.p) == 3,
        "missing Unicode polar not classified");
    check(std::string{navtool_router_last_error_v1()}.find(marker) != std::string::npos, "polar error lost UTF-8 path");
    Land missing_land;
    check(navtool_router_land_load_gshhg_v8(utf8(directory / "missing.b").c_str(), &lo, &missing_land.p) == 3,
        "missing Unicode GSHHG not classified");
    check(std::string{navtool_router_last_error_v1()}.find(marker) != std::string::npos, "GSHHG error lost UTF-8 path");
}
#include "bridge_v9_tests.inc"
} // namespace

int main(int argc, char** argv) {
    try {
        std::filesystem::create_directories(fixtures);
        test_defaults_and_validation(); test_forecast(); test_routes_and_replay(); test_holds(); test_land();
        test_polar_number_parsing();
        test_unicode_asset_paths();
        test_coastal_v9();
        const bool diagnostics = argc == 2 && std::string{argv[1]} == "--diagnostics";
        check(argc == 1 || diagnostics,"only --diagnostics is supported");
        for (bool mirrored : {false,true}) for (bool island : {false,true}) test_strategic(mirrored,island,diagnostics);
        std::cout << "ABI8 tests passed; fixture directory: " << fixtures << "\n"
                  << "sizes options=" << sizeof(navtool_router_options_v8) << " request=" << sizeof(navtool_router_request_v8)
                  << " progress=" << sizeof(navtool_router_progress_v8) << " point=" << sizeof(navtool_router_route_point_v8) << '\n';
        return 0;
    } catch (const std::exception& e) { std::cerr << e.what() << '\n'; return 1; }
}
