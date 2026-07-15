#include "navtool_router_bridge.h"

#include <eccodes.h>

#include <chrono>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <fstream>
#include <filesystem>
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

struct ProgressCapture {
    size_t count{};
    int64_t previous_time{};
    uint64_t previous_time_steps{};
    bool valid{true};
};

void capture_progress(
    const navtool_router_progress_v1* progress,
    void* user_data) {
    auto* capture = static_cast<ProgressCapture*>(user_data);
    if (capture == nullptr || progress == nullptr) {
        return;
    }
    capture->valid =
        capture->valid &&
        progress->isochrone_points != nullptr &&
        progress->isochrone_point_count > 0U &&
        progress->provisional_route_points != nullptr &&
        progress->provisional_route_point_count > 0U &&
        (capture->count == 0U ||
         progress->isochrone_utc_epoch_seconds > capture->previous_time) &&
        progress->diagnostics.time_steps ==
            capture->previous_time_steps + 1U &&
        progress->provisional_route_points[
            progress->provisional_route_point_count - 1U]
                .utc_epoch_seconds ==
            progress->isochrone_utc_epoch_seconds;
    capture->previous_time = progress->isochrone_utc_epoch_seconds;
    capture->previous_time_steps = progress->diagnostics.time_steps;
    ++capture->count;
}

std::filesystem::path create_grib_with_missing_v_step() {
    const auto output_path =
        std::filesystem::temp_directory_path() /
        ("navtool-incomplete-" +
         std::to_string(
             std::chrono::steady_clock::now().time_since_epoch().count()) +
         ".grib");
    std::FILE* input = std::fopen(NAVTOOL_ROUTER_SAMPLE_GRIB, "rb");
    if (input == nullptr) {
        throw std::runtime_error("could not open sample GRIB for incomplete fixture");
    }

    std::ofstream output{output_path, std::ios::binary};
    bool skipped_v = false;
    int error = CODES_SUCCESS;
    while (codes_handle* handle =
               codes_handle_new_from_file(nullptr, input, PRODUCT_GRIB, &error)) {
        char short_name[32]{};
        size_t short_name_length = sizeof(short_name);
        if (codes_get_string(
                handle,
                "shortName",
                short_name,
                &short_name_length) != CODES_SUCCESS) {
            codes_handle_delete(handle);
            std::fclose(input);
            throw std::runtime_error("could not read sample GRIB shortName");
        }

        if (!skipped_v && std::string{short_name} == "10v") {
            skipped_v = true;
            codes_handle_delete(handle);
            continue;
        }

        const void* message = nullptr;
        size_t message_size = 0U;
        if (codes_get_message(handle, &message, &message_size) != CODES_SUCCESS) {
            codes_handle_delete(handle);
            std::fclose(input);
            throw std::runtime_error("could not copy sample GRIB message");
        }
        output.write(
            static_cast<const char*>(message),
            static_cast<std::streamsize>(message_size));
        codes_handle_delete(handle);
    }
    std::fclose(input);
    output.close();
    if (error != CODES_SUCCESS || !skipped_v) {
        std::filesystem::remove(output_path);
        throw std::runtime_error("could not create incomplete GRIB fixture");
    }
    return output_path;
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

#if NAVTOOL_ROUTER_HAS_PROGRESS_CALLBACK
        route_json = nullptr;
        route_json_length = 0U;
        ProgressCapture progress_capture;
        require_ok(
            navtool_router_calculate_route_streaming_v1(
                forecast,
                48.25,
                -123.65,
                48.25,
                -123.35,
                &departure,
                capture_progress,
                &progress_capture,
                &route_json,
                &route_json_length),
            "calculate streaming route");
        require(progress_capture.count > 0U, "streaming route reported no progress");
        require(progress_capture.valid, "streaming route progress was invalid");
        require(route_json != nullptr, "streaming route JSON was not allocated");
        require(
            route_json_length == std::strlen(route_json),
            "streaming route JSON length mismatch");
        navtool_router_bridge_free_v1(route_json);
#endif

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

        // ---- GRIB inspection API ----

        // Null checks
        require(
            navtool_router_inspect_grib_v1(nullptr, nullptr) ==
                NAVTOOL_ROUTER_STATUS_INVALID_ARGUMENT_V1,
            "null path and descriptor were accepted");
        require(
            navtool_router_inspect_grib_v1(
                NAVTOOL_ROUTER_SAMPLE_GRIB,
                nullptr) ==
                NAVTOOL_ROUTER_STATUS_INVALID_ARGUMENT_V1,
            "null descriptor was accepted");
        require(
            navtool_router_inspect_grib_v1(
                nullptr,
                new navtool_router_grib_descriptor_v1{}) ==
                NAVTOOL_ROUTER_STATUS_INVALID_ARGUMENT_V1,
            "null path was accepted");

        // Non-existent file
        {
            navtool_router_grib_descriptor_v1 missing_desc{};
            require(
                navtool_router_inspect_grib_v1(
                    "/nonexistent/path/forecast.grib",
                    &missing_desc) ==
                    NAVTOOL_ROUTER_STATUS_FILE_IO_V1,
                "missing GRIB file was not reported as FILE_IO");
        }

        // Successful inspection of the sample GRIB
        navtool_router_grib_descriptor_v1 desc{};
        require_ok(
            navtool_router_inspect_grib_v1(NAVTOOL_ROUTER_SAMPLE_GRIB, &desc),
            "inspect sample GRIB");

        // Model should be NOAA GFS (centre 7)
        require(
            desc.model_id == NAVTOOL_ROUTER_MODEL_NOAA_GFS_V1,
            "sample GRIB model should be NOAA GFS");

        // Init time must be before first valid time
        require(
            desc.init_utc_epoch_seconds <= desc.first_valid_utc_epoch_seconds,
            "init time must not be after first valid time");

        // Valid time range must be ordered
        require(
            desc.first_valid_utc_epoch_seconds <=
                desc.last_valid_utc_epoch_seconds,
            "first valid time must not be after last valid time");

        // Init time is plausible (after year 2000, before year 2100)
        constexpr int64_t kYear2000Epoch = 946684800LL;
        constexpr int64_t kYear2100Epoch = 4102444800LL;
        require(
            desc.init_utc_epoch_seconds > kYear2000Epoch &&
                desc.init_utc_epoch_seconds < kYear2100Epoch,
            "sample GRIB init time is implausible");

        // Bounds should be finite and ordered
        require(
            std::isfinite(desc.south_latitude_degrees) &&
                std::isfinite(desc.north_latitude_degrees) &&
                std::isfinite(desc.west_longitude_degrees) &&
                std::isfinite(desc.east_longitude_degrees),
            "GRIB descriptor bounds contain non-finite values");
        require(
            desc.south_latitude_degrees <= desc.north_latitude_degrees,
            "south latitude exceeds north latitude");
        require(
            desc.south_latitude_degrees >= -90.0 &&
                desc.north_latitude_degrees <= 90.0,
            "latitude bounds are out of range");
        require(
            desc.west_longitude_degrees >= -180.0 &&
                desc.west_longitude_degrees <= 180.0 &&
                desc.east_longitude_degrees >= -180.0 &&
                desc.east_longitude_degrees <= 180.0,
            "longitude bounds are out of range");

        const auto incomplete_grib = create_grib_with_missing_v_step();
        navtool_router_grib_descriptor_v1 incomplete_desc{};
        require(
            navtool_router_inspect_grib_v1(
                incomplete_grib.string().c_str(),
                &incomplete_desc) ==
                NAVTOOL_ROUTER_STATUS_INCOMPLETE_FORECAST_V1,
            "GRIB with an unpaired wind step was accepted");
        std::filesystem::remove(incomplete_grib);

        std::cout << "Navtool router bridge tests passed\n";
        return EXIT_SUCCESS;
    } catch (const std::exception& exception) {
        std::cerr << exception.what() << '\n';
        return EXIT_FAILURE;
    }
}
