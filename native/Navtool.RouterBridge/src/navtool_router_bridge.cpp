#include "navtool_router_bridge.h"

#include "sailroute/sailroute.hpp"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <exception>
#include <filesystem>
#include <limits>
#include <new>
#include <optional>
#include <string>
#include <utility>

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
        const sailroute::Router router{forecast->weather};
        auto route = router.optimize(request);
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
    });
}

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

}  // extern "C"

static_assert(sizeof(navtool_router_status_v1) == 4U);
static_assert(sizeof(navtool_router_forecast_metadata_v1) == 40U);
static_assert(sizeof(navtool_router_wind_sample_v1) == 24U);
