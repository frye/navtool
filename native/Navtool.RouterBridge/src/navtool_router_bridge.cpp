#include "navtool_router_bridge.h"

#include "sailroute/sailroute.hpp"

#include <eccodes.h>

#include <algorithm>
#include <cerrno>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <exception>
#include <filesystem>
#include <limits>
#include <new>
#include <optional>
#include <set>
#include <string>
#include <utility>
#include <vector>

struct navtool_router_forecast_v1 {
    explicit navtool_router_forecast_v1(sailroute::WeatherDataset value)
        : weather(std::move(value)) {}

    sailroute::WeatherDataset weather;
};

namespace {

thread_local std::string last_error;

void clear_error() {
    last_error.clear();
}

navtool_router_status_v1 fail(
    navtool_router_status_v1 status,
    std::string message) {
    last_error = std::move(message);
    return status;
}

navtool_router_status_v1 map_error(const sailroute::Error& error) {
    using sailroute::ErrorCode;
    navtool_router_status_v1 status = NAVTOOL_ROUTER_STATUS_INTERNAL_ERROR_V1;
    switch (error.code) {
        case ErrorCode::invalid_argument:
            status = NAVTOOL_ROUTER_STATUS_INVALID_ARGUMENT_V1;
            break;
        case ErrorCode::file_io:
            status = NAVTOOL_ROUTER_STATUS_FILE_IO_V1;
            break;
        case ErrorCode::grib_decode:
            status = NAVTOOL_ROUTER_STATUS_FORECAST_DECODE_V1;
            break;
        case ErrorCode::unsupported_grib:
            status = NAVTOOL_ROUTER_STATUS_UNSUPPORTED_FORECAST_V1;
            break;
        case ErrorCode::incomplete_forecast:
            status = NAVTOOL_ROUTER_STATUS_INCOMPLETE_FORECAST_V1;
            break;
        case ErrorCode::departure_outside_forecast:
        case ErrorCode::coordinate_outside_forecast:
        case ErrorCode::forecast_exhausted:
            status = NAVTOOL_ROUTER_STATUS_OUTSIDE_FORECAST_V1;
            break;
        case ErrorCode::no_route:
            status = NAVTOOL_ROUTER_STATUS_NO_ROUTE_V1;
            break;
        case ErrorCode::output_error:
            status = NAVTOOL_ROUTER_STATUS_OUTPUT_ERROR_V1;
            break;
        case ErrorCode::invalid_polar:
            status = NAVTOOL_ROUTER_STATUS_INTERNAL_ERROR_V1;
            break;
    }
    return fail(status, error.message);
}

template <typename Function>
navtool_router_status_v1 protect(Function&& function) noexcept {
    clear_error();
    try {
        return std::forward<Function>(function)();
    } catch (const std::bad_alloc&) {
        return fail(
            NAVTOOL_ROUTER_STATUS_ALLOCATION_FAILURE_V1,
            "native bridge allocation failed");
    } catch (const std::exception& exception) {
        return fail(
            NAVTOOL_ROUTER_STATUS_INTERNAL_ERROR_V1,
            std::string{"native bridge exception: "} + exception.what());
    } catch (...) {
        return fail(
            NAVTOOL_ROUTER_STATUS_INTERNAL_ERROR_V1,
            "native bridge encountered an unknown exception");
    }
}

bool valid_coordinate(double latitude, double longitude) noexcept {
    return sailroute::is_valid({latitude, longitude});
}

bool valid_bounds(
    double south,
    double west,
    double north,
    double east) noexcept {
    return std::isfinite(south) && std::isfinite(west) &&
           std::isfinite(north) && std::isfinite(east) &&
           south >= -90.0 && north <= 90.0 && south <= north &&
           west >= -180.0 && west <= 180.0 &&
           east >= -180.0 && east <= 180.0;
}

sailroute::TimePoint from_epoch(int64_t seconds) {
    return sailroute::TimePoint{std::chrono::seconds{seconds}};
}

int64_t to_epoch(sailroute::TimePoint time) {
    return std::chrono::duration_cast<std::chrono::seconds>(
               time.time_since_epoch())
        .count();
}

navtool_router_status_v1 copy_utf8(
    const std::string& value,
    char** out_text,
    size_t* out_length) {
    if (value.size() == std::numeric_limits<size_t>::max()) {
        return fail(
            NAVTOOL_ROUTER_STATUS_ALLOCATION_FAILURE_V1,
            "UTF-8 result is too large to allocate");
    }
    auto* copy = static_cast<char*>(std::malloc(value.size() + 1U));
    if (copy == nullptr) {
        return fail(
            NAVTOOL_ROUTER_STATUS_ALLOCATION_FAILURE_V1,
            "unable to allocate UTF-8 result");
    }
    std::memcpy(copy, value.data(), value.size());
    copy[value.size()] = '\0';
    *out_text = copy;
    *out_length = value.size();
    return static_cast<navtool_router_status_v1>(
        NAVTOOL_ROUTER_STATUS_OK_V1);
}

template <typename Loader>
navtool_router_status_v1 load_forecast(
    const char* path,
    navtool_router_forecast_v1** out_forecast,
    Loader&& loader) {
    if (out_forecast == nullptr) {
        return fail(
            NAVTOOL_ROUTER_STATUS_INVALID_ARGUMENT_V1,
            "out_forecast must not be null");
    }
    *out_forecast = nullptr;
    if (path == nullptr || path[0] == '\0') {
        return fail(
            NAVTOOL_ROUTER_STATUS_INVALID_ARGUMENT_V1,
            "GRIB path must be a non-empty UTF-8 string");
    }

    const auto* utf8_begin = reinterpret_cast<const char8_t*>(path);
    auto weather = std::forward<Loader>(loader)(
        std::filesystem::path{std::u8string{utf8_begin}});
    if (!weather) {
        return map_error(weather.error());
    }
    *out_forecast =
        new navtool_router_forecast_v1{std::move(weather.value())};
    return static_cast<navtool_router_status_v1>(
        NAVTOOL_ROUTER_STATUS_OK_V1);
}

#if NAVTOOL_ROUTER_HAS_PROGRESS_CALLBACK
navtool_router_coordinate_v1 copy_coordinate(
    sailroute::Coordinate coordinate) noexcept {
    return {
        coordinate.latitude_degrees,
        coordinate.longitude_degrees};
}

navtool_router_route_point_v1 copy_route_point(
    const sailroute::RoutePoint& point) noexcept {
    return {
        copy_coordinate(point.position),
        to_epoch(point.time),
        point.heading_degrees,
        point.boat_speed_knots,
        point.true_wind_speed_knots,
        point.true_wind_direction_degrees,
        point.cumulative_distance_nautical_miles};
}

navtool_router_diagnostics_v1 copy_diagnostics(
    const sailroute::RouteDiagnostics& diagnostics) noexcept {
    return {
        static_cast<uint64_t>(diagnostics.expanded_nodes),
        static_cast<uint64_t>(diagnostics.generated_candidates),
        static_cast<uint64_t>(diagnostics.retained_candidates),
        static_cast<uint64_t>(diagnostics.time_steps)};
}
#endif

navtool_router_status_v1 calculate_route(
    const navtool_router_forecast_v1* forecast,
    double start_latitude_degrees,
    double start_longitude_degrees,
    double destination_latitude_degrees,
    double destination_longitude_degrees,
    const int64_t* departure_utc_epoch_seconds,
    navtool_router_progress_callback_v1 on_progress,
    void* progress_user_data,
    char** out_route_json_utf8,
    size_t* out_route_json_length) {
    if (out_route_json_utf8 != nullptr) {
        *out_route_json_utf8 = nullptr;
    }
    if (out_route_json_length != nullptr) {
        *out_route_json_length = 0U;
    }
    if (forecast == nullptr || out_route_json_utf8 == nullptr ||
        out_route_json_length == nullptr) {
        return fail(
            NAVTOOL_ROUTER_STATUS_INVALID_ARGUMENT_V1,
            "forecast and route JSON outputs must not be null");
    }
    if (!valid_coordinate(
            start_latitude_degrees,
            start_longitude_degrees) ||
        !valid_coordinate(
            destination_latitude_degrees,
            destination_longitude_degrees)) {
        return fail(
            NAVTOOL_ROUTER_STATUS_INVALID_ARGUMENT_V1,
            "route coordinates must be finite canonical latitude/longitude values");
    }

    sailroute::RouteRequest request;
    request.start = {
        start_latitude_degrees,
        start_longitude_degrees};
    request.destination = {
        destination_latitude_degrees,
        destination_longitude_degrees};
    if (departure_utc_epoch_seconds != nullptr) {
        request.departure_time =
            from_epoch(*departure_utc_epoch_seconds);
    }

#if NAVTOOL_ROUTER_HAS_PROGRESS_CALLBACK
    sailroute::RoutingProgressCallback progress_callback;
    if (on_progress != nullptr) {
        progress_callback =
            [on_progress, progress_user_data](
                const sailroute::RoutingProgress& progress) {
                std::vector<navtool_router_coordinate_v1> isochrone_points;
                isochrone_points.reserve(progress.isochrone.points.size());
                for (const sailroute::Coordinate point :
                     progress.isochrone.points) {
                    isochrone_points.push_back(copy_coordinate(point));
                }

                std::vector<navtool_router_route_point_v1> route_points;
                route_points.reserve(progress.provisional_route.size());
                for (const sailroute::RoutePoint& point :
                     progress.provisional_route) {
                    route_points.push_back(copy_route_point(point));
                }

                const navtool_router_progress_v1 bridge_progress{
                    to_epoch(progress.isochrone.time),
                    isochrone_points.data(),
                    static_cast<uint64_t>(isochrone_points.size()),
                    route_points.data(),
                    static_cast<uint64_t>(route_points.size()),
                    copy_diagnostics(progress.diagnostics)};
                on_progress(&bridge_progress, progress_user_data);
            };
    }
#else
    static_cast<void>(on_progress);
    static_cast<void>(progress_user_data);
#endif

    const sailroute::Router router{forecast->weather};
#if NAVTOOL_ROUTER_HAS_PROGRESS_CALLBACK
    auto route = router.optimize(request, progress_callback);
#else
    auto route = router.optimize(request);
#endif
    if (!route) {
        return map_error(route.error());
    }
    auto json = sailroute::route_to_json(route.value());
    if (!json) {
        return map_error(json.error());
    }
    return copy_utf8(
        json.value(),
        out_route_json_utf8,
        out_route_json_length);
}

// ---------- GRIB inspection helpers ----------

struct GribFileCloser {
    void operator()(std::FILE* f) const noexcept {
        if (f) {
            std::fclose(f);
        }
    }
};

struct GribHandleDeleter {
    void operator()(codes_handle* h) const noexcept {
        if (h) {
            codes_handle_delete(h);
        }
    }
};

using GribFilePtr = std::unique_ptr<std::FILE, GribFileCloser>;
using GribHandlePtr = std::unique_ptr<codes_handle, GribHandleDeleter>;

std::optional<long> optional_long_grib_key(
    codes_handle* h,
    const char* key) noexcept {
    long value = 0;
    if (codes_get_long(h, key, &value) != CODES_SUCCESS) {
        return std::nullopt;
    }
    return value;
}

std::optional<std::string> optional_string_grib_key(
    codes_handle* h,
    const char* key) {
    size_t len = 0;
    if (codes_get_size(h, key, &len) != CODES_SUCCESS || len == 0) {
        return std::nullopt;
    }
    std::string value(len, '\0');
    if (codes_get_string(h, key, value.data(), &len) != CODES_SUCCESS) {
        return std::nullopt;
    }
    const auto null_pos = value.find('\0');
    if (null_pos != std::string::npos) {
        value.resize(null_pos);
    }
    return value;
}

enum class GribWindComponent { east, north };

std::optional<GribWindComponent> detect_10m_wind_component(
    codes_handle* h) {
    // Prefer paramId (GRIB2 standard)
    auto param_id = optional_long_grib_key(h, "paramId");
    if (param_id == 165L) {
        return GribWindComponent::east;
    }
    if (param_id == 166L) {
        return GribWindComponent::north;
    }

    // Fall back to shortName
    auto short_name = optional_string_grib_key(h, "shortName");
    if (!short_name) {
        return std::nullopt;
    }
    if (*short_name == "10u" || *short_name == "u10") {
        return GribWindComponent::east;
    }
    if (*short_name == "10v" || *short_name == "v10") {
        return GribWindComponent::north;
    }
    if (*short_name != "u" && *short_name != "v") {
        return std::nullopt;
    }

    // Generic u/v: must be at 10 m height above ground
    auto level_type = optional_string_grib_key(h, "typeOfLevel");
    auto level = optional_long_grib_key(h, "level");
    if (!level_type || !level ||
        *level_type != "heightAboveGround" || *level != 10L) {
        return std::nullopt;
    }
    return *short_name == "u" ? GribWindComponent::east : GribWindComponent::north;
}

// Returns epoch seconds, or nullopt if the encoded date/time is invalid.
std::optional<int64_t> parse_grib_datetime(
    long date,
    long time) noexcept {
    const int year = static_cast<int>(date / 10000L);
    const unsigned month = static_cast<unsigned>((date / 100L) % 100L);
    const unsigned day = static_cast<unsigned>(date % 100L);
    const int hour = static_cast<int>(time / 100L);
    const int minute = static_cast<int>(time % 100L);

    using namespace std::chrono;
    const year_month_day ymd{
        std::chrono::year{year},
        std::chrono::month{month},
        std::chrono::day{day}};
    if (!ymd.ok() || hour < 0 || hour > 23 || minute < 0 || minute > 59) {
        return std::nullopt;
    }
    return static_cast<int64_t>(
        duration_cast<seconds>(
            (sys_days{ymd} + hours{hour} + minutes{minute})
                .time_since_epoch())
            .count());
}

// Converts a GRIB longitude in [0, 360] to canonical [-180, 180].
double normalize_grib_longitude(double lon) noexcept {
    return lon > 180.0 ? lon - 360.0 : lon;
}

struct LongitudeCoverage {
    double west;   // canonical [-180, 180]
    double east;   // canonical; may be < west when the arc crosses the antimeridian
    bool global;   // true when the union spans (effectively) the full 360 degrees
};

// Computes the minimal covering longitude arc across every wind message's grid
// extent, treating longitude as a circle. Each input pair is a message's
// [firstGridPoint, lastGridPoint] longitude in GRIB degrees ([0, 360), scanning
// eastward). A single global grid yields global coverage; multiple subset windows
// (e.g. a NOMADS request split across the antimeridian) are unioned into one arc
// rather than trusting the first message alone.
LongitudeCoverage compute_longitude_coverage(
    const std::vector<std::pair<double, double>>& arcs) {
    constexpr double kEpsilon = 1e-6;
    auto wrap360 = [](double value) {
        double result = std::fmod(value, 360.0);
        if (result < 0.0) {
            result += 360.0;
        }
        return result;
    };

    // Expand each eastward arc into one or two non-wrapping intervals on [0, 360].
    std::vector<std::pair<double, double>> intervals;
    for (const auto& [first_lon, last_lon] : arcs) {
        const double start = wrap360(first_lon);
        double span = wrap360(last_lon) - start;
        if (span < 0.0) {
            span += 360.0;
        }
        const double end = start + span;
        if (end <= 360.0 + kEpsilon) {
            intervals.emplace_back(start, std::min(end, 360.0));
        } else {
            intervals.emplace_back(start, 360.0);
            intervals.emplace_back(0.0, end - 360.0);
        }
    }

    if (intervals.empty()) {
        return {-180.0, 180.0, true};
    }

    std::sort(intervals.begin(), intervals.end());
    std::vector<std::pair<double, double>> merged;
    for (const auto& interval : intervals) {
        if (!merged.empty() && interval.first <= merged.back().second + kEpsilon) {
            merged.back().second = std::max(merged.back().second, interval.second);
        } else {
            merged.push_back(interval);
        }
    }

    double covered = 0.0;
    for (const auto& interval : merged) {
        covered += interval.second - interval.first;
    }
    if (covered >= 359.0) {
        return {-180.0, 180.0, true};
    }

    // Find the largest uncovered gap on the circle; the covering arc is its
    // complement. Gaps sit between consecutive merged intervals plus the seam
    // wrapping from the last interval's end back to the first interval's start.
    double largest_gap = (360.0 - merged.back().second) + merged.front().first;
    double west_grib = merged.front().first;   // coverage resumes here after the seam gap
    double east_grib = merged.back().second;   // coverage ends here before the seam gap
    for (std::size_t i = 1; i < merged.size(); ++i) {
        const double gap = merged[i].first - merged[i - 1].second;
        if (gap > largest_gap) {
            largest_gap = gap;
            west_grib = merged[i].first;
            east_grib = merged[i - 1].second;
        }
    }

    return {
        normalize_grib_longitude(west_grib),
        normalize_grib_longitude(east_grib),
        false};
}

}  // namespace

extern "C" {

uint32_t navtool_router_bridge_abi_version_v1(void) {
    return NAVTOOL_ROUTER_BRIDGE_ABI_VERSION;
}

const char* navtool_router_last_error_v1(void) {
    return last_error.c_str();
}

navtool_router_status_v1 navtool_router_forecast_load_v1(
    const char* grib_path_utf8,
    navtool_router_forecast_v1** out_forecast) {
    return protect([&] {
        return load_forecast(
            grib_path_utf8,
            out_forecast,
            [](const std::filesystem::path& path) {
                return sailroute::WeatherDataset::load(path);
            });
    });
}

navtool_router_status_v1 navtool_router_forecast_load_bounded_v1(
    const char* grib_path_utf8,
    double south_latitude_degrees,
    double west_longitude_degrees,
    double north_latitude_degrees,
    double east_longitude_degrees,
    navtool_router_forecast_v1** out_forecast) {
    return protect([&] {
        if (!valid_bounds(
                south_latitude_degrees,
                west_longitude_degrees,
                north_latitude_degrees,
                east_longitude_degrees)) {
            return fail(
                NAVTOOL_ROUTER_STATUS_INVALID_ARGUMENT_V1,
                "forecast bounds are invalid");
        }
        return load_forecast(
            grib_path_utf8,
            out_forecast,
            [&](const std::filesystem::path& path) {
                return sailroute::WeatherDataset::load(
                    path,
                    sailroute::GeographicBounds{
                        south_latitude_degrees,
                        west_longitude_degrees,
                        north_latitude_degrees,
                        east_longitude_degrees});
            });
    });
}

navtool_router_status_v1 navtool_router_forecast_destroy_v1(
    navtool_router_forecast_v1** forecast) {
    return protect([&] {
        if (forecast == nullptr) {
            return fail(
                NAVTOOL_ROUTER_STATUS_INVALID_ARGUMENT_V1,
                "forecast pointer must not be null");
        }
        delete *forecast;
        *forecast = nullptr;
        return static_cast<navtool_router_status_v1>(
            NAVTOOL_ROUTER_STATUS_OK_V1);
    });
}

navtool_router_status_v1 navtool_router_forecast_get_metadata_v1(
    const navtool_router_forecast_v1* forecast,
    navtool_router_forecast_metadata_v1* out_metadata,
    char** out_source_utf8,
    size_t* out_source_length) {
    return protect([&] {
        if (out_source_utf8 != nullptr) {
            *out_source_utf8 = nullptr;
        }
        if (out_source_length != nullptr) {
            *out_source_length = 0U;
        }
        if (forecast == nullptr || out_metadata == nullptr ||
            out_source_utf8 == nullptr || out_source_length == nullptr) {
            return fail(
                NAVTOOL_ROUTER_STATUS_INVALID_ARGUMENT_V1,
                "forecast, metadata, source, and source length outputs must not be null");
        }

        const sailroute::ForecastMetadata& metadata =
            forecast->weather.metadata();
        *out_metadata = navtool_router_forecast_metadata_v1{
            to_epoch(metadata.first_valid_time),
            to_epoch(metadata.last_valid_time),
            static_cast<uint64_t>(metadata.latitude_count),
            static_cast<uint64_t>(metadata.longitude_count),
            static_cast<uint8_t>(metadata.global_longitude_coverage ? 1U : 0U),
            {0U, 0U, 0U, 0U, 0U, 0U, 0U}};
        return copy_utf8(
            metadata.source,
            out_source_utf8,
            out_source_length);
    });
}

navtool_router_status_v1 navtool_router_calculate_route_v1(
    const navtool_router_forecast_v1* forecast,
    double start_latitude_degrees,
    double start_longitude_degrees,
    double destination_latitude_degrees,
    double destination_longitude_degrees,
    const int64_t* departure_utc_epoch_seconds,
    char** out_route_json_utf8,
    size_t* out_route_json_length) {
    return protect([&] {
        return calculate_route(
            forecast,
            start_latitude_degrees,
            start_longitude_degrees,
            destination_latitude_degrees,
            destination_longitude_degrees,
            departure_utc_epoch_seconds,
            nullptr,
            nullptr,
            out_route_json_utf8,
            out_route_json_length);
    });
}

#if NAVTOOL_ROUTER_HAS_PROGRESS_CALLBACK
navtool_router_status_v1 navtool_router_calculate_route_streaming_v1(
    const navtool_router_forecast_v1* forecast,
    double start_latitude_degrees,
    double start_longitude_degrees,
    double destination_latitude_degrees,
    double destination_longitude_degrees,
    const int64_t* departure_utc_epoch_seconds,
    navtool_router_progress_callback_v1 on_progress,
    void* progress_user_data,
    char** out_route_json_utf8,
    size_t* out_route_json_length) {
    return protect([&] {
        return calculate_route(
            forecast,
            start_latitude_degrees,
            start_longitude_degrees,
            destination_latitude_degrees,
            destination_longitude_degrees,
            departure_utc_epoch_seconds,
            on_progress,
            progress_user_data,
            out_route_json_utf8,
            out_route_json_length);
    });
}
#endif

navtool_router_status_v1 navtool_router_sample_grid_v1(
    const navtool_router_forecast_v1* forecast,
    double south_latitude_degrees,
    double west_longitude_degrees,
    double north_latitude_degrees,
    double east_longitude_degrees,
    uint32_t latitude_count,
    uint32_t longitude_count,
    int64_t utc_epoch_seconds,
    navtool_router_wind_sample_v1* samples,
    size_t sample_count) {
    return protect([&] {
        if (forecast == nullptr || samples == nullptr) {
            return fail(
                NAVTOOL_ROUTER_STATUS_INVALID_ARGUMENT_V1,
                "forecast and samples must not be null");
        }
        if (!valid_bounds(
                south_latitude_degrees,
                west_longitude_degrees,
                north_latitude_degrees,
                east_longitude_degrees)) {
            return fail(
                NAVTOOL_ROUTER_STATUS_INVALID_ARGUMENT_V1,
                "sampling bounds are invalid");
        }
        if (latitude_count == 0U || longitude_count == 0U ||
            static_cast<size_t>(latitude_count) >
                std::numeric_limits<size_t>::max() /
                    static_cast<size_t>(longitude_count) ||
            static_cast<size_t>(latitude_count) *
                    static_cast<size_t>(longitude_count) !=
                sample_count) {
            return fail(
                NAVTOOL_ROUTER_STATUS_INVALID_ARGUMENT_V1,
                "sample_count must equal the positive latitude_count * longitude_count");
        }

        double unwrapped_east = east_longitude_degrees;
        if (unwrapped_east < west_longitude_degrees) {
            unwrapped_east += 360.0;
        }
        const auto axis_value = [](
                                    double first,
                                    double last,
                                    uint32_t index,
                                    uint32_t count) {
            if (count == 1U) {
                return (first + last) / 2.0;
            }
            return first +
                   (last - first) *
                       static_cast<double>(index) /
                       static_cast<double>(count - 1U);
        };
        const sailroute::TimePoint time = from_epoch(utc_epoch_seconds);
        for (uint32_t latitude_index = 0U;
             latitude_index < latitude_count;
             ++latitude_index) {
            const double latitude = axis_value(
                south_latitude_degrees,
                north_latitude_degrees,
                latitude_index,
                latitude_count);
            for (uint32_t longitude_index = 0U;
                 longitude_index < longitude_count;
                 ++longitude_index) {
                const double longitude = axis_value(
                    west_longitude_degrees,
                    unwrapped_east,
                    longitude_index,
                    longitude_count);
                const size_t index =
                    static_cast<size_t>(latitude_index) *
                        static_cast<size_t>(longitude_count) +
                    static_cast<size_t>(longitude_index);
                samples[index] = navtool_router_wind_sample_v1{
                    0.0,
                    0.0,
                    0U,
                    {0U, 0U, 0U, 0U, 0U, 0U, 0U}};
                auto wind = forecast->weather.interpolate(
                    {latitude, longitude},
                    time);
                if (wind) {
                    samples[index].east_mps = wind.value().east_mps;
                    samples[index].north_mps = wind.value().north_mps;
                    samples[index].valid = 1U;
                }
            }
        }
        return static_cast<navtool_router_status_v1>(
            NAVTOOL_ROUTER_STATUS_OK_V1);
    });
}

void navtool_router_bridge_free_v1(void* bridge_owned_memory) {
    std::free(bridge_owned_memory);
}

uint32_t navtool_router_bridge_preflight_v1(void) {
    return NAVTOOL_ROUTER_BRIDGE_ABI_VERSION;
}

navtool_router_status_v1 navtool_router_inspect_grib_v1(
    const char* grib_path_utf8,
    navtool_router_grib_descriptor_v1* out_descriptor) {
    return protect([&]() -> navtool_router_status_v1 {
        if (out_descriptor == nullptr) {
            return fail(
                NAVTOOL_ROUTER_STATUS_INVALID_ARGUMENT_V1,
                "out_descriptor must not be null");
        }
        if (grib_path_utf8 == nullptr || grib_path_utf8[0] == '\0') {
            return fail(
                NAVTOOL_ROUTER_STATUS_INVALID_ARGUMENT_V1,
                "GRIB path must be a non-empty UTF-8 string");
        }

        const auto* utf8_begin =
            reinterpret_cast<const char8_t*>(grib_path_utf8);
        const std::filesystem::path path{std::u8string{utf8_begin}};
        const std::string display_path = path.string();

        errno = 0;
#ifdef _WIN32
        GribFilePtr file{_wfopen(path.c_str(), L"rb")};
#else
        GribFilePtr file{std::fopen(grib_path_utf8, "rb")};
#endif
        if (!file) {
            const int open_error = errno;
            std::string message =
                "cannot open GRIB file '" + display_path + "'";
            if (open_error != 0) {
                message += ": ";
                message += std::strerror(open_error);
            }
            return fail(NAVTOOL_ROUTER_STATUS_FILE_IO_V1, std::move(message));
        }

        std::optional<long> detected_centre;
        std::optional<int64_t> init_epoch;
        int64_t first_valid = std::numeric_limits<int64_t>::max();
        int64_t last_valid = std::numeric_limits<int64_t>::min();
        std::optional<double> south_lat;
        std::optional<double> north_lat;
        std::vector<std::pair<double, double>> lon_arcs;
        std::set<int64_t> u_valid_times;
        std::set<int64_t> v_valid_times;
        std::size_t grib_count = 0U;
        int decode_status = CODES_SUCCESS;

        while (true) {
            GribHandlePtr handle{codes_handle_new_from_file(
                nullptr,
                file.get(),
                PRODUCT_GRIB,
                &decode_status)};
            if (!handle) {
                break;
            }
            ++grib_count;

            long edition = 0;
            if (codes_get_long(handle.get(), "edition", &edition) !=
                    CODES_SUCCESS ||
                (edition != 1 && edition != 2)) {
                return fail(
                    NAVTOOL_ROUTER_STATUS_UNSUPPORTED_FORECAST_V1,
                    "GRIB file contains an unsupported edition");
            }

            const auto component =
                detect_10m_wind_component(handle.get());
            if (!component) {
                continue;
            }
            // Model centre — must be consistent across all wind messages.
            const auto centre =
                optional_long_grib_key(handle.get(), "centre");
            if (!centre) {
                return fail(
                    NAVTOOL_ROUTER_STATUS_FORECAST_DECODE_V1,
                    "cannot read 'centre' key from GRIB wind message in '" +
                        display_path + "'");
            }
            if (!detected_centre) {
                detected_centre = *centre;
            } else if (*detected_centre != *centre) {
                return fail(
                    NAVTOOL_ROUTER_STATUS_UNSUPPORTED_FORECAST_V1,
                    "GRIB file '" + display_path +
                        "' mixes wind messages from different model centres "
                        "(" + std::to_string(*detected_centre) + " and " +
                        std::to_string(*centre) + "); "
                        "model identity is ambiguous");
            }

            // Init time — must be consistent (same model run).
            const auto data_date =
                optional_long_grib_key(handle.get(), "dataDate");
            const auto data_time =
                optional_long_grib_key(handle.get(), "dataTime");
            if (!data_date || !data_time) {
                return fail(
                    NAVTOOL_ROUTER_STATUS_FORECAST_DECODE_V1,
                    "cannot read init-time keys from GRIB wind message in '" +
                        display_path + "'");
            }
            const auto this_init = parse_grib_datetime(*data_date, *data_time);
            if (!this_init) {
                return fail(
                    NAVTOOL_ROUTER_STATUS_FORECAST_DECODE_V1,
                    "GRIB wind message in '" + display_path +
                        "' has an invalid init time (dataDate=" +
                        std::to_string(*data_date) +
                        " dataTime=" + std::to_string(*data_time) + ")");
            }
            if (!init_epoch) {
                init_epoch = *this_init;
            } else if (*init_epoch != *this_init) {
                return fail(
                    NAVTOOL_ROUTER_STATUS_UNSUPPORTED_FORECAST_V1,
                    "GRIB file '" + display_path +
                        "' contains wind messages from different model runs; "
                        "use a single-run file");
            }

            // Validity time range.
            const auto validity_date =
                optional_long_grib_key(handle.get(), "validityDate");
            const auto validity_time =
                optional_long_grib_key(handle.get(), "validityTime");
            if (!validity_date || !validity_time) {
                return fail(
                    NAVTOOL_ROUTER_STATUS_FORECAST_DECODE_V1,
                    "cannot read validity-time keys from GRIB wind message in '" +
                        display_path + "'");
            }
            const auto this_valid =
                parse_grib_datetime(*validity_date, *validity_time);
            if (!this_valid) {
                return fail(
                    NAVTOOL_ROUTER_STATUS_FORECAST_DECODE_V1,
                    "GRIB wind message in '" + display_path +
                        "' has an invalid validity time");
            }
            first_valid = std::min(first_valid, *this_valid);
            last_valid = std::max(last_valid, *this_valid);
            if (*component == GribWindComponent::east) {
                u_valid_times.insert(*this_valid);
            } else {
                v_valid_times.insert(*this_valid);
            }

            // Grid bounds — collect union across all wind messages.
            double first_lat = 0.0;
            double last_lat = 0.0;
            double first_lon = 0.0;
            double last_lon = 0.0;
            if (codes_get_double(
                    handle.get(),
                    "latitudeOfFirstGridPointInDegrees",
                    &first_lat) != CODES_SUCCESS ||
                codes_get_double(
                    handle.get(),
                    "latitudeOfLastGridPointInDegrees",
                    &last_lat) != CODES_SUCCESS ||
                codes_get_double(
                    handle.get(),
                    "longitudeOfFirstGridPointInDegrees",
                    &first_lon) != CODES_SUCCESS ||
                codes_get_double(
                    handle.get(),
                    "longitudeOfLastGridPointInDegrees",
                    &last_lon) != CODES_SUCCESS) {
                return fail(
                    NAVTOOL_ROUTER_STATUS_FORECAST_DECODE_V1,
                    "cannot read grid-bounds keys from GRIB wind message in '" +
                        display_path + "'");
            }
            const double msg_south = std::min(first_lat, last_lat);
            const double msg_north = std::max(first_lat, last_lat);
            if (!south_lat || msg_south < *south_lat) {
                south_lat = msg_south;
            }
            if (!north_lat || msg_north > *north_lat) {
                north_lat = msg_north;
            }
            // Grid longitudinal extent — accumulate every wind message's arc so the
            // union is computed across all of them (like the latitude bounds), which
            // is required for artifacts assembled from multiple subset windows.
            lon_arcs.emplace_back(first_lon, last_lon);
        }

        if (decode_status != CODES_SUCCESS) {
            return fail(
                NAVTOOL_ROUTER_STATUS_FORECAST_DECODE_V1,
                "error while scanning GRIB messages in '" + display_path + "'");
        }
        if (grib_count == 0U) {
            return fail(
                NAVTOOL_ROUTER_STATUS_FORECAST_DECODE_V1,
                "'" + display_path + "' contains no decodable GRIB messages");
        }
        if (u_valid_times.empty() || v_valid_times.empty()) {
            return fail(
                NAVTOOL_ROUTER_STATUS_INCOMPLETE_FORECAST_V1,
                "'" + display_path +
                    "' does not contain both 10 m U and V wind components; "
                    "a complete wind forecast requires paired eastward (U) "
                    "and northward (V) fields");
        }
        if (u_valid_times != v_valid_times) {
            return fail(
                NAVTOOL_ROUTER_STATUS_INCOMPLETE_FORECAST_V1,
                "'" + display_path +
                    "' does not contain paired 10 m U and V wind components "
                    "for every forecast validity time");
        }

        // Map centre code to supported model identity.
        int32_t model_id = NAVTOOL_ROUTER_MODEL_UNKNOWN_V1;
        if (detected_centre) {
            if (*detected_centre == 7L) {
                model_id = NAVTOOL_ROUTER_MODEL_NOAA_GFS_V1;
            } else if (*detected_centre == 98L) {
                model_id = NAVTOOL_ROUTER_MODEL_ECMWF_IFS_V1;
            } else {
                return fail(
                    NAVTOOL_ROUTER_STATUS_UNSUPPORTED_FORECAST_V1,
                    "GRIB centre code " +
                        std::to_string(*detected_centre) +
                        " is not a supported forecast model; "
                        "expected NCEP (centre=7) for NOAA GFS or "
                        "ECMWF (centre=98) for IFS");
            }
        }

        const LongitudeCoverage coverage = compute_longitude_coverage(lon_arcs);
        const double west = coverage.west;
        const double east = coverage.east;

        *out_descriptor = navtool_router_grib_descriptor_v1{
            *init_epoch,
            first_valid,
            last_valid,
            *south_lat,
            west,
            *north_lat,
            east,
            model_id,
            {0U, 0U, 0U, 0U}};
        return static_cast<navtool_router_status_v1>(
            NAVTOOL_ROUTER_STATUS_OK_V1);
    });
}

}  // extern "C"

static_assert(sizeof(navtool_router_grib_descriptor_v1) == 64U);

static_assert(sizeof(navtool_router_status_v1) == 4U);
static_assert(sizeof(navtool_router_forecast_metadata_v1) == 40U);
static_assert(sizeof(navtool_router_wind_sample_v1) == 24U);
static_assert(sizeof(navtool_router_coordinate_v1) == 16U);
static_assert(sizeof(navtool_router_route_point_v1) == 64U);
static_assert(sizeof(navtool_router_diagnostics_v1) == 32U);
