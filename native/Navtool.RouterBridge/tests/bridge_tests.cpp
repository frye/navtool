#include "navtool_router_bridge.h"

#include <cmath>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <limits>
#include <stdexcept>
#include <string>
#include <vector>

namespace {

void require(bool condition, const char* message) {
    if (!condition) {
        throw std::runtime_error(message);
    }
}

void require_ok(navtool_router_status_v1 status, const char* operation) {
    if (status != NAVTOOL_ROUTER_STATUS_OK_V1) {
        throw std::runtime_error(
            std::string{operation} + ": " +
            navtool_router_last_error_v1());
    }
}

}  // namespace

int main() {
    try {
        require(
            navtool_router_bridge_abi_version_v1() ==
                NAVTOOL_ROUTER_BRIDGE_ABI_VERSION,
            "unexpected bridge ABI version");

        navtool_router_forecast_v1* forecast = nullptr;
        require(
            navtool_router_forecast_load_v1(
                NAVTOOL_ROUTER_SAMPLE_GRIB,
                nullptr) ==
                NAVTOOL_ROUTER_STATUS_INVALID_ARGUMENT_V1,
            "null load output was accepted");
        require(
            navtool_router_forecast_load_v1(nullptr, &forecast) ==
                NAVTOOL_ROUTER_STATUS_INVALID_ARGUMENT_V1,
            "null GRIB path was accepted");
        require(
            navtool_router_forecast_destroy_v1(nullptr) ==
                NAVTOOL_ROUTER_STATUS_INVALID_ARGUMENT_V1,
            "null destroy pointer was accepted");
        require_ok(
            navtool_router_forecast_destroy_v1(&forecast),
            "destroy null forecast");
        require_ok(
            navtool_router_forecast_load_v1(
                NAVTOOL_ROUTER_SAMPLE_GRIB,
                &forecast),
            "load sample forecast");
        require(forecast != nullptr, "load returned a null forecast");

        navtool_router_forecast_metadata_v1 metadata{};
        char* source = nullptr;
        size_t source_length = 0U;
        require_ok(
            navtool_router_forecast_get_metadata_v1(
                forecast,
                &metadata,
                &source,
                &source_length),
            "read metadata");
        require(metadata.latitude_count == 3U, "unexpected latitude count");
        require(metadata.longitude_count == 3U, "unexpected longitude count");
        require(
            metadata.first_valid_utc_epoch_seconds <
                metadata.last_valid_utc_epoch_seconds,
            "invalid forecast time range");
        require(source != nullptr, "metadata source was not allocated");
        require(
            source_length == std::strlen(source),
            "metadata source length mismatch");
        require(
            std::string{source}.find("sample.grib") != std::string::npos,
            "metadata source does not name sample.grib");
        navtool_router_bridge_free_v1(source);

        std::vector<navtool_router_wind_sample_v1> samples(9U);
        require_ok(
            navtool_router_sample_grid_v1(
                forecast,
                48.0,
                -123.75,
                48.5,
                -123.25,
                3U,
                3U,
                metadata.first_valid_utc_epoch_seconds,
                samples.data(),
                samples.size()),
            "sample forecast grid");
        for (const auto& sample : samples) {
            require(sample.valid == 1U, "expected a valid wind sample");
            require(
                std::isfinite(sample.east_mps) &&
                    std::isfinite(sample.north_mps),
                "wind sample was not finite");
        }

        int64_t departure = metadata.first_valid_utc_epoch_seconds;
        char* route_json = nullptr;
        size_t route_json_length = 0U;
        require_ok(
            navtool_router_calculate_route_v1(
                forecast,
                48.25,
                -123.65,
                48.25,
                -123.35,
                &departure,
                &route_json,
                &route_json_length),
            "calculate route");
        require(route_json != nullptr, "route JSON was not allocated");
        require(
            route_json_length == std::strlen(route_json),
            "route JSON length mismatch");
        require(
            std::string{route_json}.find("\"points\"") != std::string::npos,
            "route JSON does not contain points");
        navtool_router_bridge_free_v1(route_json);

        route_json = nullptr;
        route_json_length = 0U;
        require(
            navtool_router_calculate_route_v1(
                forecast,
                std::numeric_limits<double>::quiet_NaN(),
                -123.65,
                48.25,
                -123.35,
                &departure,
                &route_json,
                &route_json_length) ==
                NAVTOOL_ROUTER_STATUS_INVALID_ARGUMENT_V1,
            "non-finite route coordinate was accepted");
        require(
            route_json == nullptr && route_json_length == 0U,
            "failed route call populated outputs");
        require(
            navtool_router_sample_grid_v1(
                forecast,
                48.0,
                -123.75,
                48.5,
                -123.25,
                3U,
                3U,
                departure,
                samples.data(),
                samples.size() - 1U) ==
                NAVTOOL_ROUTER_STATUS_INVALID_ARGUMENT_V1,
            "invalid sample count was accepted");
        require(
            std::strlen(navtool_router_last_error_v1()) != 0U,
            "invalid call did not provide a thread-local error");

        require_ok(
            navtool_router_forecast_destroy_v1(&forecast),
            "destroy forecast");
        require(forecast == nullptr, "destroy did not clear forecast handle");
        require_ok(
            navtool_router_forecast_destroy_v1(&forecast),
            "destroy forecast twice");

        require_ok(
            navtool_router_forecast_load_bounded_v1(
                NAVTOOL_ROUTER_SAMPLE_GRIB,
                48.1,
                -123.7,
                48.2,
                -123.6,
                &forecast),
            "load bounded sample forecast");
        source = nullptr;
        source_length = 0U;
        require_ok(
            navtool_router_forecast_get_metadata_v1(
                forecast,
                &metadata,
                &source,
                &source_length),
            "read bounded metadata");
        require(metadata.latitude_count == 2U, "bounded latitude crop failed");
        require(metadata.longitude_count == 2U, "bounded longitude crop failed");
        navtool_router_bridge_free_v1(source);

        navtool_router_wind_sample_v1 outside_sample{};
        require_ok(
            navtool_router_sample_grid_v1(
                forecast,
                48.25,
                -123.65,
                48.25,
                -123.65,
                1U,
                1U,
                metadata.first_valid_utc_epoch_seconds,
                &outside_sample,
                1U),
            "sample outside bounded forecast");
        require(
            outside_sample.valid == 0U,
            "bounded forecast accepted an outside coordinate");
        require_ok(
            navtool_router_forecast_destroy_v1(&forecast),
            "destroy bounded forecast");

        std::cout << "Navtool router bridge tests passed\n";
        return EXIT_SUCCESS;
    } catch (const std::exception& exception) {
        std::cerr << exception.what() << '\n';
        return EXIT_FAILURE;
    }
}
