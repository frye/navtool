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

void require_codes_ok(int status, const char* operation) {
    if (status != CODES_SUCCESS) {
        throw std::runtime_error(
            std::string{operation} + ": " + codes_get_error_message(status));
    }
}

struct ProgressCapture {
    size_t count{};
    int64_t previous_time{};
    uint64_t previous_time_steps{};
    bool valid{true};
};

struct ContourProgressCapture {
    size_t count{};
    int64_t previous_time{};
    uint64_t previous_time_steps{};
    bool valid{true};
};

struct FrontProgressCapture {
    size_t count{};
    int64_t previous_time{};
    uint64_t previous_time_steps{};
    bool valid{true};
};

struct DisplayProgressCapture {
    size_t count{};
    int64_t previous_time{};
    uint64_t previous_time_steps{};
    bool valid{true};
};

struct SegmentEligibilityCapture {
    size_t count{};
};

uint8_t reject_all_segments(
    const navtool_router_coordinate_v1* parent,
    const navtool_router_coordinate_v1* candidate,
    void* user_data) {
    auto* capture = static_cast<SegmentEligibilityCapture*>(user_data);
    if (capture == nullptr || parent == nullptr || candidate == nullptr) {
        return 0U;
    }
    capture->count++;
    return 0U;
}

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

void capture_contour_progress(
    const navtool_router_progress_v2* progress,
    void* user_data) {
    auto* capture = static_cast<ContourProgressCapture*>(user_data);
    if (capture == nullptr || progress == nullptr) {
        return;
    }
    bool segments_valid = progress->contour_segments != nullptr &&
                          progress->contour_segment_count > 0U;
    for (uint64_t index = 0U;
         segments_valid && index < progress->contour_segment_count;
         ++index) {
        const auto& segment = progress->contour_segments[index];
        segments_valid =
            segment.point_count > 0U &&
            segment.closed <= 1U &&
            segment.point_offset <= progress->contour_point_count &&
            segment.point_count <=
                progress->contour_point_count - segment.point_offset;
    }
    capture->valid =
        capture->valid &&
        progress->contour_points != nullptr &&
        progress->contour_point_count > 0U &&
        segments_valid &&
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

void capture_front_progress(
    const navtool_router_progress_v3* progress,
    void* user_data) {
    auto* capture = static_cast<FrontProgressCapture*>(user_data);
    if (capture == nullptr || progress == nullptr) {
        return;
    }
    bool segments_valid = progress->front_segments != nullptr &&
                          progress->front_segment_count > 0U;
    for (uint64_t index = 0U;
         segments_valid && index < progress->front_segment_count;
         ++index) {
        const auto& segment = progress->front_segments[index];
        segments_valid =
            segment.point_count > 0U &&
            segment.point_offset <= progress->front_point_count &&
            segment.point_count <=
                progress->front_point_count - segment.point_offset;
    }
    bool route_ends_on_front = false;
    if (progress->front_points != nullptr &&
        progress->provisional_route_points != nullptr &&
        progress->provisional_route_point_count > 0U) {
        const auto& route_end = progress->provisional_route_points[
            progress->provisional_route_point_count - 1U].position;
        for (uint64_t index = 0U;
             index < progress->front_point_count;
             ++index) {
            route_ends_on_front =
                route_ends_on_front ||
                (progress->front_points[index].latitude_degrees ==
                     route_end.latitude_degrees &&
                 progress->front_points[index].longitude_degrees ==
                     route_end.longitude_degrees);
        }
    }
    capture->valid =
        capture->valid &&
        progress->front_points != nullptr &&
        progress->front_point_count > 0U &&
        segments_valid &&
        route_ends_on_front &&
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

void capture_display_progress(
    const navtool_router_progress_v5* progress,
    void* user_data) {
    auto* capture = static_cast<DisplayProgressCapture*>(user_data);
    if (capture == nullptr || progress == nullptr) {
        return;
    }
    bool contours_valid = progress->contour_segments != nullptr &&
                          progress->contour_segment_count > 0U;
    for (uint64_t index = 0U;
         contours_valid && index < progress->contour_segment_count;
         ++index) {
        const auto& segment = progress->contour_segments[index];
        contours_valid =
            segment.point_count > 0U &&
            segment.closed <= 1U &&
            segment.point_offset <= progress->contour_point_count &&
            segment.point_count <=
                progress->contour_point_count - segment.point_offset;
    }
    bool fronts_valid = progress->front_segments != nullptr &&
                        progress->front_segment_count > 0U;
    for (uint64_t index = 0U;
         fronts_valid && index < progress->front_segment_count;
         ++index) {
        const auto& segment = progress->front_segments[index];
        fronts_valid =
            segment.point_count > 0U &&
            segment.point_offset <= progress->front_point_count &&
            segment.point_count <=
                progress->front_point_count - segment.point_offset;
    }
    bool route_ends_on_front = false;
    if (progress->front_points != nullptr &&
        progress->provisional_route_points != nullptr &&
        progress->provisional_route_point_count > 0U) {
        const auto& route_end = progress->provisional_route_points[
            progress->provisional_route_point_count - 1U].position;
        for (uint64_t index = 0U;
             index < progress->front_point_count;
             ++index) {
            route_ends_on_front =
                route_ends_on_front ||
                (progress->front_points[index].latitude_degrees ==
                     route_end.latitude_degrees &&
                 progress->front_points[index].longitude_degrees ==
                     route_end.longitude_degrees);
        }
    }
    capture->valid =
        capture->valid &&
        progress->contour_points != nullptr &&
        progress->contour_point_count > 0U &&
        contours_valid &&
        progress->front_points != nullptr &&
        progress->front_point_count > 0U &&
        fronts_valid &&
        route_ends_on_front &&
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

std::filesystem::path create_grib_through_step(long maximum_step) {
    const auto output_path =
        std::filesystem::temp_directory_path() /
        ("navtool-short-" +
         std::to_string(
             std::chrono::steady_clock::now().time_since_epoch().count()) +
         ".grib");
    std::FILE* input = std::fopen(NAVTOOL_ROUTER_SAMPLE_GRIB, "rb");
    if (input == nullptr) {
        throw std::runtime_error("could not open sample GRIB for short fixture");
    }

    std::ofstream output{output_path, std::ios::binary};
    bool copied_message = false;
    int error = CODES_SUCCESS;
    while (codes_handle* handle =
               codes_handle_new_from_file(nullptr, input, PRODUCT_GRIB, &error)) {
        long step = 0;
        if (codes_get_long(handle, "step", &step) != CODES_SUCCESS) {
            codes_handle_delete(handle);
            std::fclose(input);
            throw std::runtime_error("could not read sample GRIB step");
        }

        if (step <= maximum_step) {
            const void* message = nullptr;
            size_t message_size = 0U;
            if (codes_get_message(handle, &message, &message_size) !=
                CODES_SUCCESS) {
                codes_handle_delete(handle);
                std::fclose(input);
                throw std::runtime_error("could not copy short GRIB message");
            }
            output.write(
                static_cast<const char*>(message),
                static_cast<std::streamsize>(message_size));
            copied_message = true;
        }
        codes_handle_delete(handle);
    }
    std::fclose(input);
    output.close();
    if (error != CODES_SUCCESS || !copied_message) {
        std::filesystem::remove(output_path);
        throw std::runtime_error("could not create short GRIB fixture");
    }
    return output_path;
}

std::filesystem::path create_tiled_grib() {
    const auto output_path =
        std::filesystem::temp_directory_path() /
        ("navtool-tiled-" +
         std::to_string(
             std::chrono::steady_clock::now().time_since_epoch().count()) +
         ".grib");
    constexpr long tile_point_count = 41L;
    constexpr double grid_step = 0.25;
    const double latitude_bands[][2] = {
        {50.0, 40.0},
        {60.0, 50.0},
    };
    const double longitude_bands[][2] = {
        {220.0, 230.0},
        {230.0, 240.0},
        {240.0, 250.0},
    };
    bool first_message = true;

    try {
        for (const auto& latitude_band : latitude_bands) {
            for (const auto& longitude_band : longitude_bands) {
                for (const auto* short_name : {"10u", "10v"}) {
                    codes_handle* handle =
                        codes_grib_handle_new_from_samples(
                            nullptr,
                            "regular_ll_sfc_grib2");
                    if (handle == nullptr) {
                        throw std::runtime_error(
                            "unable to create tiled ecCodes GRIB sample");
                    }

                    try {
                        require_codes_ok(
                            codes_set_long(handle, "Ni", tile_point_count),
                            "set tiled Ni");
                        require_codes_ok(
                            codes_set_long(handle, "Nj", tile_point_count),
                            "set tiled Nj");
                        require_codes_ok(
                            codes_set_double(
                                handle,
                                "latitudeOfFirstGridPointInDegrees",
                                latitude_band[0]),
                            "set tiled first latitude");
                        require_codes_ok(
                            codes_set_double(
                                handle,
                                "latitudeOfLastGridPointInDegrees",
                                latitude_band[1]),
                            "set tiled last latitude");
                        require_codes_ok(
                            codes_set_double(
                                handle,
                                "longitudeOfFirstGridPointInDegrees",
                                longitude_band[0]),
                            "set tiled first longitude");
                        require_codes_ok(
                            codes_set_double(
                                handle,
                                "longitudeOfLastGridPointInDegrees",
                                longitude_band[1]),
                            "set tiled last longitude");
                        require_codes_ok(
                            codes_set_double(
                                handle,
                                "iDirectionIncrementInDegrees",
                                grid_step),
                            "set tiled longitude increment");
                        require_codes_ok(
                            codes_set_double(
                                handle,
                                "jDirectionIncrementInDegrees",
                                grid_step),
                            "set tiled latitude increment");
                        require_codes_ok(
                            codes_set_long(handle, "iScansNegatively", 0),
                            "set tiled i scan");
                        require_codes_ok(
                            codes_set_long(handle, "jScansPositively", 0),
                            "set tiled j scan");
                        require_codes_ok(
                            codes_set_long(handle, "dataDate", 20260803),
                            "set tiled date");
                        require_codes_ok(
                            codes_set_long(handle, "dataTime", 1800),
                            "set tiled time");
                        require_codes_ok(
                            codes_set_long(handle, "forecastTime", 7),
                            "set tiled forecast time");
                        std::size_t short_name_size =
                            std::char_traits<char>::length(short_name);
                        require_codes_ok(
                            codes_set_string(
                                handle,
                                "shortName",
                                short_name,
                                &short_name_size),
                            "set tiled wind component");
                        require_codes_ok(
                            codes_set_long(handle, "level", 10),
                            "set tiled wind level");
                        const std::vector<double> values(
                            static_cast<std::size_t>(
                                tile_point_count * tile_point_count),
                            std::string{short_name} == "10u" ? 12.0 : 4.0);
                        require_codes_ok(
                            codes_set_double_array(
                                handle,
                                "values",
                                values.data(),
                                values.size()),
                            "set tiled values");
                        require_codes_ok(
                            codes_write_message(
                                handle,
                                output_path.string().c_str(),
                                first_message ? "w" : "a"),
                            "write tiled GRIB message");
                        first_message = false;
                    } catch (...) {
                        codes_handle_delete(handle);
                        throw;
                    }
                    codes_handle_delete(handle);
                }
            }
        }
    } catch (...) {
        std::filesystem::remove(output_path);
        throw;
    }

    return output_path;
}

std::filesystem::path create_ecmwf_grib(bool mixed_run = false) {
    const auto output_path =
        std::filesystem::temp_directory_path() /
        ("navtool-ecmwf-" +
         std::to_string(
             std::chrono::steady_clock::now().time_since_epoch().count()) +
         ".grib2");
    constexpr long longitude_count = 360L;
    constexpr long latitude_count = 181L;
    bool first_message = true;

    try {
        for (const long forecast_hour : {0L, 3L}) {
            for (const auto* short_name : {"10u", "10v"}) {
                codes_handle* handle =
                    codes_grib_handle_new_from_samples(
                        nullptr,
                        "regular_ll_sfc_grib2");
                if (handle == nullptr) {
                    throw std::runtime_error(
                        "unable to create ECMWF ecCodes GRIB sample");
                }

                try {
                    require_codes_ok(
                        codes_set_long(handle, "centre", 98L),
                        "set ECMWF centre");
                    require_codes_ok(
                        codes_set_long(handle, "Ni", longitude_count),
                        "set ECMWF Ni");
                    require_codes_ok(
                        codes_set_long(handle, "Nj", latitude_count),
                        "set ECMWF Nj");
                    require_codes_ok(
                        codes_set_double(
                            handle,
                            "latitudeOfFirstGridPointInDegrees",
                            90.0),
                        "set ECMWF first latitude");
                    require_codes_ok(
                        codes_set_double(
                            handle,
                            "latitudeOfLastGridPointInDegrees",
                            -90.0),
                        "set ECMWF last latitude");
                    require_codes_ok(
                        codes_set_double(
                            handle,
                            "longitudeOfFirstGridPointInDegrees",
                            0.0),
                        "set ECMWF first longitude");
                    require_codes_ok(
                        codes_set_double(
                            handle,
                            "longitudeOfLastGridPointInDegrees",
                            359.0),
                        "set ECMWF last longitude");
                    require_codes_ok(
                        codes_set_double(
                            handle,
                            "iDirectionIncrementInDegrees",
                            1.0),
                        "set ECMWF longitude increment");
                    require_codes_ok(
                        codes_set_double(
                            handle,
                            "jDirectionIncrementInDegrees",
                            1.0),
                        "set ECMWF latitude increment");
                    require_codes_ok(
                        codes_set_long(handle, "iScansNegatively", 0L),
                        "set ECMWF i scan");
                    require_codes_ok(
                        codes_set_long(handle, "jScansPositively", 0L),
                        "set ECMWF j scan");
                    const bool use_mixed_run =
                        mixed_run &&
                        forecast_hour == 3L &&
                        std::string{short_name} == "10v";
                    require_codes_ok(
                        codes_set_long(
                            handle,
                            "dataDate",
                            use_mixed_run ? 20260804L : 20260803L),
                        "set ECMWF date");
                    require_codes_ok(
                        codes_set_long(handle, "dataTime", 1800L),
                        "set ECMWF time");
                    require_codes_ok(
                        codes_set_long(handle, "forecastTime", forecast_hour),
                        "set ECMWF forecast time");
                    const long parameter_id =
                        std::string{short_name} == "10u" ? 165L : 166L;
                    require_codes_ok(
                        codes_set_long(handle, "paramId", parameter_id),
                        "set ECMWF wind parameter");
                    require_codes_ok(
                        codes_set_long(handle, "level", 10L),
                        "set ECMWF wind level");
                    const std::vector<double> values(
                        static_cast<std::size_t>(
                            longitude_count * latitude_count),
                        parameter_id == 165L ? 12.0 : 4.0);
                    require_codes_ok(
                        codes_set_double_array(
                            handle,
                            "values",
                            values.data(),
                            values.size()),
                        "set ECMWF values");
                    require_codes_ok(
                        codes_write_message(
                            handle,
                            output_path.string().c_str(),
                            first_message ? "w" : "a"),
                        "write ECMWF GRIB message");
                    first_message = false;
                } catch (...) {
                    codes_handle_delete(handle);
                    throw;
                }
                codes_handle_delete(handle);
            }
        }
    } catch (...) {
        std::filesystem::remove(output_path);
        throw;
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
        require(
            navtool_router_bridge_capabilities_v1() ==
                NAVTOOL_ROUTER_CAPABILITY_LAND_SEGMENT_CONSTRAINT_V1,
            "bridge did not advertise land segment constraints");

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
        DisplayProgressCapture display_progress_capture;
        require_ok(
            navtool_router_calculate_route_streaming_v5(
                forecast,
                48.25,
                -123.65,
                48.25,
                -123.35,
                &departure,
                capture_display_progress,
                &display_progress_capture,
                nullptr,
                nullptr,
                &route_json,
                &route_json_length),
            "calculate combined display streaming route");
        require(
            display_progress_capture.count > 0U,
            "combined display streaming route reported no progress");
        require(
            display_progress_capture.valid,
            "combined display streaming route progress was invalid");
        require(
            route_json != nullptr,
            "combined display streaming route JSON was not allocated");
        require(
            route_json_length == std::strlen(route_json),
            "combined display streaming route JSON length mismatch");
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
        ContourProgressCapture contour_progress_capture;
        require_ok(
            navtool_router_calculate_route_streaming_v2(
                forecast,
                48.25,
                -123.65,
                48.25,
                -123.35,
                &departure,
                capture_contour_progress,
                &contour_progress_capture,
                &route_json,
                &route_json_length),
            "calculate contour streaming route");
        require(
            contour_progress_capture.count > 0U,
            "contour streaming route reported no progress");
        require(
            contour_progress_capture.valid,
            "contour streaming route progress was invalid");
        require(
            route_json != nullptr,
            "contour streaming route JSON was not allocated");
        require(
            route_json_length == std::strlen(route_json),
            "contour streaming route JSON length mismatch");
        navtool_router_bridge_free_v1(route_json);

        route_json = nullptr;
        route_json_length = 0U;
        FrontProgressCapture front_progress_capture;
        require_ok(
            navtool_router_calculate_route_streaming_v3(
                forecast,
                48.25,
                -123.65,
                48.25,
                -123.35,
                &departure,
                capture_front_progress,
                &front_progress_capture,
                &route_json,
                &route_json_length),
            "calculate front streaming route");
        require(
            front_progress_capture.count > 0U,
            "front streaming route reported no progress");
        require(
            front_progress_capture.valid,
            "front streaming route progress was invalid");
        require(
            route_json != nullptr,
            "front streaming route JSON was not allocated");
        require(
            route_json_length == std::strlen(route_json),
            "front streaming route JSON length mismatch");
        navtool_router_bridge_free_v1(route_json);

        route_json = nullptr;
        route_json_length = 0U;
        SegmentEligibilityCapture segment_capture;
        require(
            navtool_router_calculate_route_streaming_v5(
                forecast,
                48.25,
                -123.65,
                48.25,
                -123.35,
                &departure,
                nullptr,
                nullptr,
                reject_all_segments,
                &segment_capture,
                &route_json,
                &route_json_length) ==
                NAVTOOL_ROUTER_STATUS_NO_ROUTE_V1,
            "rejecting every segment did not prevent route creation");
        require(
            segment_capture.count > 0U,
            "segment eligibility callback was not invoked");
        require(
            route_json == nullptr && route_json_length == 0U,
            "rejected route unexpectedly returned route JSON");

        route_json = nullptr;
        route_json_length = 0U;
        SegmentEligibilityCapture v4_segment_capture;
        require(
            navtool_router_calculate_route_streaming_v4(
                forecast,
                48.25,
                -123.65,
                48.25,
                -123.35,
                &departure,
                nullptr,
                nullptr,
                reject_all_segments,
                &v4_segment_capture,
                &route_json,
                &route_json_length) ==
                NAVTOOL_ROUTER_STATUS_NO_ROUTE_V1,
            "ABI v4 segment rejection did not prevent route creation");
        require(
            v4_segment_capture.count > 0U,
            "ABI v4 segment eligibility callback was not invoked");
        require(
            route_json == nullptr && route_json_length == 0U,
            "ABI v4 rejected route unexpectedly returned route JSON");

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

        const auto short_grib = create_grib_through_step(9L);
        try {
            require_ok(
                navtool_router_forecast_load_v1(
                    short_grib.string().c_str(),
                    &forecast),
                "load short forecast");
            require_ok(
                navtool_router_forecast_get_metadata_v1(
                    forecast,
                    &metadata,
                    &source,
                    &source_length),
                "read short forecast metadata");
            navtool_router_bridge_free_v1(source);

            departure = metadata.first_valid_utc_epoch_seconds;
            route_json = nullptr;
            route_json_length = 0U;
            DisplayProgressCapture exhausted_progress;
            require_ok(
                navtool_router_calculate_route_streaming_v5(
                    forecast,
                    48.05,
                    -123.70,
                    48.45,
                    -123.30,
                    &departure,
                    capture_display_progress,
                    &exhausted_progress,
                    nullptr,
                    nullptr,
                    &route_json,
                    &route_json_length),
                "calculate forecast-limited route");
            require(
                exhausted_progress.count > 0U && exhausted_progress.valid,
                "forecast exhaustion did not preserve valid display progress");
            require(
                route_json != nullptr && route_json_length > 0U,
                "forecast exhaustion did not return partial route JSON");
            require(
                std::string{route_json}.find(
                    "\"completion\":\"forecast_exhausted\"") !=
                    std::string::npos,
                "partial route JSON did not report forecast exhaustion");
            navtool_router_bridge_free_v1(route_json);
            require_ok(
                navtool_router_forecast_destroy_v1(&forecast),
                "destroy short forecast");
            std::filesystem::remove(short_grib);
        } catch (...) {
            navtool_router_forecast_destroy_v1(&forecast);
            std::filesystem::remove(short_grib);
            throw;
        }

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

        const auto tiled_grib = create_tiled_grib();
        try {
            require_ok(
                navtool_router_forecast_load_bounded_v1(
                    tiled_grib.string().c_str(),
                    43.0,
                    -134.0,
                    54.0,
                    -114.25,
                    &forecast),
                "load Port Townsend-Ucluelet tiled forecast");
            require_ok(
                navtool_router_forecast_get_metadata_v1(
                    forecast,
                    &metadata,
                    &source,
                    &source_length),
                "read tiled forecast metadata");
            require(
                metadata.latitude_count == 45U,
                "tiled latitude mosaic was not cropped to the requested bounds");
            require(
                metadata.longitude_count == 80U,
                "tiled longitude mosaic was not cropped to the requested bounds");
            navtool_router_bridge_free_v1(source);

            navtool_router_wind_sample_v1 tiled_sample{};
            require_ok(
                navtool_router_sample_grid_v1(
                    forecast,
                    48.5,
                    -123.0,
                    48.5,
                    -123.0,
                    1U,
                    1U,
                    metadata.first_valid_utc_epoch_seconds,
                    &tiled_sample,
                    1U),
                "sample tiled forecast");
            require(
                tiled_sample.valid == 1U &&
                    std::abs(tiled_sample.east_mps - 12.0) < 1e-9 &&
                    std::abs(tiled_sample.north_mps - 4.0) < 1e-9,
                "tiled forecast interpolation returned unexpected wind");
            require_ok(
                navtool_router_forecast_destroy_v1(&forecast),
                "destroy tiled forecast");
            std::filesystem::remove(tiled_grib);
        } catch (...) {
            navtool_router_forecast_destroy_v1(&forecast);
            std::filesystem::remove(tiled_grib);
            throw;
        }

        const auto ecmwf_grib = create_ecmwf_grib();
        try {
            navtool_router_grib_descriptor_v1 ecmwf_desc{};
            require_ok(
                navtool_router_inspect_grib_v1(
                    ecmwf_grib.string().c_str(),
                    &ecmwf_desc),
                "inspect ECMWF GRIB");
            require(
                ecmwf_desc.model_id == NAVTOOL_ROUTER_MODEL_ECMWF_IFS_V1,
                "generated ECMWF GRIB has the wrong model identity");
            require(
                ecmwf_desc.first_valid_utc_epoch_seconds <
                    ecmwf_desc.last_valid_utc_epoch_seconds,
                "generated ECMWF GRIB does not have paired validity times");
            require(
                ecmwf_desc.south_latitude_degrees == -90.0 &&
                    ecmwf_desc.north_latitude_degrees == 90.0,
                "generated ECMWF GRIB does not report global latitude coverage");

            require_ok(
                navtool_router_forecast_load_bounded_v1(
                    ecmwf_grib.string().c_str(),
                    48.0,
                    -124.0,
                    49.0,
                    -122.0,
                    &forecast),
                "load bounded ECMWF forecast");
            require_ok(
                navtool_router_forecast_get_metadata_v1(
                    forecast,
                    &metadata,
                    &source,
                    &source_length),
                "read bounded ECMWF metadata");
            require(
                metadata.latitude_count == 2U &&
                    metadata.longitude_count == 3U,
                "ECMWF global forecast was not cropped to the requested corridor");
            navtool_router_bridge_free_v1(source);

            navtool_router_wind_sample_v1 ecmwf_sample{};
            require_ok(
                navtool_router_sample_grid_v1(
                    forecast,
                    48.5,
                    -123.0,
                    48.5,
                    -123.0,
                    1U,
                    1U,
                    metadata.first_valid_utc_epoch_seconds,
                    &ecmwf_sample,
                    1U),
                "sample bounded ECMWF forecast");
            require(
                ecmwf_sample.valid == 1U &&
                    std::abs(ecmwf_sample.east_mps - 12.0) < 1e-9 &&
                    std::abs(ecmwf_sample.north_mps - 4.0) < 1e-9,
                "ECMWF weather sampling returned unexpected wind");

            departure = metadata.first_valid_utc_epoch_seconds;
            route_json = nullptr;
            route_json_length = 0U;
            require_ok(
                navtool_router_calculate_route_v1(
                    forecast,
                    48.5,
                    -123.8,
                    48.5,
                    -123.2,
                    &departure,
                    &route_json,
                    &route_json_length),
                "calculate ECMWF route");
            require(
                route_json != nullptr && route_json_length > 0U,
                "ECMWF route calculation returned no route");
            navtool_router_bridge_free_v1(route_json);
            require_ok(
                navtool_router_forecast_destroy_v1(&forecast),
                "destroy ECMWF forecast");
            std::filesystem::remove(ecmwf_grib);
        } catch (...) {
            navtool_router_forecast_destroy_v1(&forecast);
            std::filesystem::remove(ecmwf_grib);
            throw;
        }

        const auto mixed_ecmwf_grib = create_ecmwf_grib(true);
        navtool_router_grib_descriptor_v1 mixed_ecmwf_desc{};
        require(
            navtool_router_inspect_grib_v1(
                mixed_ecmwf_grib.string().c_str(),
                &mixed_ecmwf_desc) ==
                NAVTOOL_ROUTER_STATUS_UNSUPPORTED_FORECAST_V1,
            "mixed-run ECMWF GRIB was accepted");
        std::filesystem::remove(mixed_ecmwf_grib);

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
