import Foundation

enum L10n {
    static func string(_ key: StaticString) -> String {
        SharedL10n.text(String(describing: key), bundle: .main)
    }

    static func string(_ key: String) -> String {
        SharedL10n.text(key, bundle: .main)
    }

    static var tripStartedTitle: String { string("trip.started.title") }
    static var tripStartedBody: String { string("trip.started.body") }
    static var tripEndedTitle: String { string("trip.ended.title") }
    static var tripDiscardedTitle: String { string("trip.discarded.title") }
    static var tripDiscardedBody: String { string("trip.discarded.body") }
    static var recordingStarted: String { string("recording.started") }
    static var categoryPersonal: String { string("category.personal") }
    static var categoryBusiness: String { string("category.business") }
    static var speedKmh: String { string("unit.speed_kmh") }
    static var stop: String { string("action.stop") }
    static var delete: String { string("action.delete") }
    static var share: String { string("action.share") }
    static var shareCardPreparing: String { string("share.card.preparing") }
    static var shareCardPreviewTitle: String { string("share.card.preview.title") }

    static func shareCaptionWhenRange(date: String, start: String, end: String) -> String {
        String(format: string("share.caption.when_range"), date, start, end)
    }

    static func shareCaptionWhenStart(date: String, start: String) -> String {
        String(format: string("share.caption.when_start"), date, start)
    }

    static var notificationsTitle: String { string("notifications.title") }
    static var notificationsEmptyTitle: String { string("notifications.empty.title") }
    static var notificationsEmptyMessage: String { string("notifications.empty.message") }
    static var notificationsClearAll: String { string("notifications.clear_all") }
    static var notificationsMarkAllRead: String { string("notifications.mark_all_read") }
    static var notificationsOpen: String { string("notifications.open") }

    static var pause: String { string("action.pause") }
    static var resume: String { string("action.resume") }
    static var recordingPaused: String { string("recording.paused") }
    static var settingsRecordingSection: String { string("settings.recording.section") }
    static var settingsAutoRecording: String { string("settings.recording.auto") }
    static var settingsRecordingSounds: String { string("settings.recording.sounds") }
    static var settingsRecordingSensitivitySection: String { string("settings.recording.sensitivity") }
    static var settingsIdleTimeout: String { string("settings.recording.idle_timeout") }
    static var settingsLowSpeedStop: String { string("settings.recording.low_speed_stop") }
    static var settingsRecordingStartSpeed: String { string("settings.recording.start_speed") }
    static var settingsRecordingStopSpeed: String { string("settings.recording.stop_speed") }
    static var settingsStopSpeed: String { string("settings.recording.trip_stop_speed") }
    static var settingsStopMinimumDistance: String { string("settings.recording.min_distance") }
    static var settingsStopMinimumDuration: String { string("settings.recording.min_duration") }
    static var settingsTripStopMinimumDuration: String { string("settings.recording.trip_stop_min_duration") }
    static var tripStopsSection: String { string("trip.stops.section") }
    static var tripEditTimesSection: String { string("trip.edit.times") }
    static var tripTrimPointsSection: String { string("trip.trim.points") }
    static var tripTrimHead: String { string("trip.trim.head") }
    static var tripTrimTail: String { string("trip.trim.tail") }
    static var tripStartedAt: String { string("trip.started_at") }
    static var tripEndedAt: String { string("trip.ended_at") }
    static var tripDetailTitle: String { string("trip.detail.title") }
    static var tripPointStart: String { string("trip.point.start") }
    static var tripPointEnd: String { string("trip.point.end") }
    static var tripPointStop: String { string("trip.point.stop") }
    static var tripMapOfflineHint: String { string("trip.map.offline_hint") }
    static var orphanStaleNotificationTitle: String { string("orphan.stale.title") }
    static var orphanStaleNotificationBody: String { string("orphan.stale.body") }
    static var all: String { string("filter.all") }
    static var filterDate: String { string("filter.date") }
    static var filterCategory: String { string("filter.category") }
    static var filterVehicle: String { string("filter.vehicle") }
    static var filterPlace: String { string("filter.place") }
    static var duration: String { string("label.duration") }
    static var movingDuration: String { string("label.moving_duration") }
    static var movingDurationHelpTitle: String { string("label.moving_duration.help.title") }
    static var movingDurationHelpBody: String { string("label.moving_duration.help.body") }
    static var currentSpeed: String { string("label.current_speed") }
    static var liveMapSpeed: String { string("recording.live_map.speed") }
    static var maxAbbr: String { string("label.max_abbr") }
    static var avgAbbr: String { string("label.avg_abbr") }
    static var labelDistance: String { string("label.distance") }
    static var placeHome: String { string("place.home") }
    static var placeWork: String { string("place.work") }
    static var placeOther: String { string("place.other") }

    static func placeNearName(_ name: String) -> String {
        String(format: string("place.near_name"), name)
    }

    static var tripsEmptyTitle: String { string("trips.empty.title") }
    static var tripsEmptyMessage: String { string("trips.empty.message") }
    static var tripsEmptyFilteredTitle: String { string("trips.empty.filtered.title") }
    static var tripsEmptyFilteredMessage: String { string("trips.empty.filtered.message") }
    static var emptyTripsTitle: String { string("empty.trips.title") }
    static var emptyTripsMessage: String { string("empty.trips.message") }
    static var emptyTripsStepStart: String { string("empty.trips.step.start") }
    static var emptyTripsStepDrive: String { string("empty.trips.step.drive") }
    static var emptyTripsStepReview: String { string("empty.trips.step.review") }
    static var emptyTripsAuto: String { string("empty.trips.auto") }
    static var emptyTripsRecordingTitle: String { string("empty.trips.recording.title") }
    static var emptyTripsRecordingMessage: String { string("empty.trips.recording.message") }
    static var emptyJournalHighlightMap: String { string("empty.journal.highlight.map") }
    static var emptyJournalHighlightTotals: String { string("empty.journal.highlight.totals") }
    static var emptyJournalHighlightSuggest: String { string("empty.journal.highlight.suggest") }
    static var emptyStatsTitle: String { string("empty.stats.title") }
    static var emptyStatsMessage: String { string("empty.stats.message") }
    static var emptyStatsHighlightWeek: String { string("empty.stats.highlight.week") }
    static var emptyStatsHighlightSpeed: String { string("empty.stats.highlight.speed") }
    static var emptyStatsHighlightFuel: String { string("empty.stats.highlight.fuel") }
    static var emptyRecapTitle: String { string("empty.recap.title") }
    static var emptyRecapMessage: String { string("empty.recap.message") }
    static var emptyRecapHighlightAwards: String { string("empty.recap.highlight.awards") }
    static var emptyRecapHighlightRoutes: String { string("empty.recap.highlight.routes") }
    static var emptyVehicleHighlightAuto: String { string("empty.vehicle.highlight.auto") }
    static var emptyVehicleHighlightCare: String { string("empty.vehicle.highlight.care") }
    static var emptyVehicleHighlightCosts: String { string("empty.vehicle.highlight.costs") }
    static var emptyGoTrips: String { string("empty.goTrips") }
    static var tripsSearchEmpty: String { string("trips.search.empty") }
    static var tripsMergeTitle: String { string("trips.merge.title") }
    static func tripsMergeMessage(_ count: Int) -> String {
        String(format: string("trips.merge.message"), count)
    }
    static var tripsMergeNeedsTwo: String { string("trips.merge.error.needs_two") }
    static var tripsMergeProgress: String { string("trips.merge.progress") }
    static var tripsMergedTitle: String { string("trips.merged.title") }
    static func tripsMergedBody(_ count: Int) -> String {
        String(format: string("trips.merged.body"), count)
    }
    static var a11ySelected: String { string("a11y.selected") }
    static var a11yNotSelected: String { string("a11y.not_selected") }
    static var tripEditCategory: String { string("trip.edit.category") }
    static var tripEditNote: String { string("trip.edit.note") }
    static var tripEditNotePlaceholder: String { string("trip.edit.note_placeholder") }
    static var tripEditFieldPrevious: String { string("trip.edit.field.previous") }
    static var tripEditFieldNext: String { string("trip.edit.field.next") }
    /// Shared a11y labels for form field navigation (same strings as trip edit).
    static var fieldPrevious: String { tripEditFieldPrevious }
    static var fieldNext: String { tripEditFieldNext }
    static var tripEditSave: String { string("trip.edit.save") }
    static var tripEditFuelSection: String { string("trip.edit.fuel.section") }
    static var tripEditFuelHelpTitle: String { string("trip.edit.fuel.help.title") }
    static var tripEditFuelHelpBody: String { string("trip.edit.fuel.help.body") }

    static func tripEditFuelPreview(_ cost: String) -> String {
        String(format: string("trip.edit.fuel.preview"), cost)
    }

    static var fuelUnitCostPerLiter: String { string("fuel.unit.cost_per_liter") }
    static var fuelUnitCostPerKWh: String { string("fuel.unit.cost_per_kwh") }
    static var actionClose: String { string("action.close") }
    static var actionAdd: String { string("action.add") }
    static var mapStylePicker: String { string("map.style.picker") }
    static func settingsAutoDeleteDays(_ days: Int) -> String {
        String(format: string("settings.privacy.auto_delete.days"), days)
    }
    static var settingsPrivacyRadiusUnit: String { string("settings.privacy.radius_unit") }
    static var categorySection: String { string("category.section") }
    static var categoryBuiltinBadge: String { string("category.builtin_badge") }
    static var categoryNewPlaceholder: String { string("category.new_placeholder") }
    static var fuelUnitKWhPer100km: String { string("fuel.unit.kwh_per_100km") }
    static var fuelUnitLPer100km: String { string("fuel.unit.l_per_100km") }
    static var sectionToday: String { string("section.today") }
    static var sectionYesterday: String { string("section.yesterday") }
    static var sectionThisWeek: String { string("section.this_week") }
    static var sectionThisMonth: String { string("section.this_month") }
    static var sectionOlder: String { string("section.older") }
    static var searchTrips: String { string("search.trips") }
    static var searchWorking: String { string("search.working") }
    static var tripsFilters: String { string("trips.filters") }
    static var tripsFiltersClear: String { string("trips.filters.clear") }
    static var statsFiltersClear: String { string("stats.filters.clear") }
    static var statsSummaryLoading: String { string("stats.summary.loading") }

    static func statsFiltersActiveCount(_ count: Int) -> String {
        String(format: string("stats.filters.active_count"), count)
    }
    static var actionMerge: String { string("action.merge") }
    static var actionCategory: String { string("action.category") }
    static var actionAcceptCategory: String { string("action.accept_category") }

    static func actionAcceptSuggestedCategory(_ name: String) -> String {
        String(format: string("action.accept_suggested_category"), name)
    }

    static func tripCategorySuggested(_ name: String) -> String {
        String(format: string("trip.category.suggested"), name)
    }
    static var mapFullscreen: String { string("map.fullscreen") }
    static var mapExitFullscreen: String { string("map.exit_fullscreen") }
    static var mapStyleLight: String { string("map.style.light") }
    static var mapStyleDark: String { string("map.style.dark") }
    static var speedLegendSlow: String { string("speed.legend.slow") }
    static var tripSpeedChart: String { string("trip.speed_chart") }
    static var speedLegendMedium: String { string("speed.legend.medium") }
    static var speedLegendFast: String { string("speed.legend.fast") }
    static var tripSummary: String { string("trip.summary") }
    static var estimatedFuel: String { string("label.estimated_fuel") }
    static var avgFuel: String { string("label.avg_fuel") }
    static var avgFuelHelpTitle: String { string("label.avg_fuel.help.title") }
    static var avgFuelHelpBody: String { string("label.avg_fuel.help.body") }
    static var dynamicFuel: String { string("label.dynamic_fuel") }
    static var dynamicFuelHelpTitle: String { string("label.dynamic_fuel.help.title") }
    static var dynamicFuelHelpBody: String { string("label.dynamic_fuel.help.body") }
    static var statsDynamicFuelHelpBody: String { string("stats.dynamic_fuel.help.body") }
    static var fuelEfficiency: String { string("label.fuel_efficiency") }
    static var fuelEfficiencyHelpTitle: String { string("label.fuel_efficiency.help.title") }
    static var fuelEfficiencyHelpBody: String { string("label.fuel_efficiency.help.body") }
    static var fuelTraffic: String { string("label.fuel_traffic") }
    static var fuelTrafficHelpTitle: String { string("label.fuel_traffic.help.title") }
    static var fuelTrafficHelpBody: String { string("label.fuel_traffic.help.body") }
    static var fuelFactorsHelpTitle: String { string("label.fuel_factors.help.title") }
    static var fuelFactorsHelpBody: String { string("label.fuel_factors.help.body") }
    static var measuredFuel: String { string("label.measured_fuel") }
    static var measuredFuelHelpTitle: String { string("label.measured_fuel.help.title") }
    static var measuredFuelHelpBody: String { string("label.measured_fuel.help.body") }
    static var statsFuelVolume: String { string("stats.fuel_volume") }
    static var statsFuelVolumeHelpTitle: String { string("stats.fuel_volume.help.title") }
    static var statsFuelVolumeHelpBody: String { string("stats.fuel_volume.help.body") }
    static var statsFuelRate: String { string("stats.fuel_rate") }
    static var statsFuelRateHelpTitle: String { string("stats.fuel_rate.help.title") }
    static var statsFuelRateHelpBody: String { string("stats.fuel_rate.help.body") }
    static var statsFuelEfficiency: String { string("stats.fuel_efficiency") }
    static var statsMixedFuelUnits: String { string("stats.fuel_mixed_units") }
    static var statsDrivingDaysHelpTitle: String { string("stats.driving_days.help.title") }
    static var statsDrivingDaysHelpBody: String { string("stats.driving_days.help.body") }

    static func statsDrivingDays(_ count: Int, of total: Int) -> String {
        String(format: string("stats.driving_days.format"), count, total)
    }
    static var statsDynamicCostPerKmHelpTitle: String { string("stats.dynamic_cost_per_km.help.title") }
    static var statsDynamicCostPerKmHelpBody: String { string("stats.dynamic_cost_per_km.help.body") }
    static var statsDynamicCostPerTripHelpTitle: String { string("stats.dynamic_cost_per_trip.help.title") }
    static var statsDynamicCostPerTripHelpBody: String { string("stats.dynamic_cost_per_trip.help.body") }
    static var fuelTrafficLow: String { string("label.fuel_traffic.low") }
    static var fuelTrafficModerate: String { string("label.fuel_traffic.moderate") }
    static var fuelTrafficHeavy: String { string("label.fuel_traffic.heavy") }
    static var fuelTrafficUnknown: String { string("label.fuel_traffic.unknown") }
    static var fuelFactorColdStart: String { string("label.fuel_factor.cold_start") }
    static var fuelFactorIdle: String { string("label.fuel_factor.idle") }
    static var fuelFactorAccel: String { string("label.fuel_factor.accel") }
    static var fuelFactorHighSpeed: String { string("label.fuel_factor.high_speed") }
    static var fuelFactorLowSpeed: String { string("label.fuel_factor.low_speed") }
    static var fuelFactorSteady: String { string("label.fuel_factor.steady") }
    static var loggedVehicleExpensesHelpTitle: String { string("stats.compare.vehicles_help.title") }
    static var loggedVehicleExpensesHelpBody: String { string("stats.compare.vehicles_help.body") }
    static var maxSpeed: String { string("label.max_speed") }
    static var averageSpeed: String { string("label.average_speed") }
    static var cruiseSpeed: String { string("label.cruise_speed") }
    static var cruiseSpeedHelpTitle: String { string("label.cruise_speed.help.title") }
    static var cruiseSpeedHelpBody: String { string("label.cruise_speed.help.body") }
    static var mostCommonSpeed: String { string("label.most_common_speed") }
    static var mostCommonSpeedHelpTitle: String { string("label.most_common_speed.help.title") }
    static var mostCommonSpeedHelpBody: String { string("label.most_common_speed.help.body") }
    static var medianSpeed: String { string("label.median_speed") }
    static var medianSpeedHelpTitle: String { string("label.median_speed.help.title") }
    static var medianSpeedHelpBody: String { string("label.median_speed.help.body") }
    static var p90Speed: String { string("label.p90_speed") }
    static var p90SpeedHelpTitle: String { string("label.p90_speed.help.title") }
    static var p90SpeedHelpBody: String { string("label.p90_speed.help.body") }
    static var stopDuration: String { string("label.stop_duration") }
    static var fuelPetrol: String { string("fuel.petrol") }
    static var fuelDiesel: String { string("fuel.diesel") }
    static var fuelLpg: String { string("fuel.lpg") }
    static var fuelElectric: String { string("fuel.electric") }
    static var fuelHybrid: String { string("fuel.hybrid") }
    static var tripLocationOverrides: String { string("trip.location.overrides") }
    static var tripStartPlaceName: String { string("trip.start_place_name") }
    static var tripEndPlaceName: String { string("trip.end_place_name") }
    static var tripStartAddress: String { string("trip.start_address") }
    static var tripEndAddress: String { string("trip.end_address") }
    static var tripAddToFavorites: String { string("trip.add_to_favorites") }
    static var tripAddStartToFavorites: String { string("trip.add_start_to_favorites") }
    static var tripAddEndToFavorites: String { string("trip.add_end_to_favorites") }
    static var tripEditFavoritePlace: String { string("trip.edit_favorite_place") }
    static var placeAlreadySaved: String { string("place.already_saved") }
    static var placeCoordinatesField: String { string("place.coordinates.field") }
    static var placeCoordinatesPlaceholder: String { string("place.coordinates.placeholder") }
    static var placeCoordinatesApply: String { string("place.coordinates.apply") }
    static var placeCoordinatesInvalid: String { string("place.coordinates.invalid") }
    static var placeSuggestionSection: String { string("place.suggestion.section") }
    static var placePickerSelectedLocation: String { string("place.picker.selected_location") }
    static var placePickerMoveMapHint: String { string("place.picker.move_map_hint") }
    static var placePickerUseCurrentLocation: String { string("place.picker.use_current_location") }
    static var placePickerResolvingAddress: String { string("place.picker.resolving_address") }
    static var placePickerNearbySection: String { string("place.picker.nearby_section") }
    static var placePickerSearchPlaceholder: String { string("place.picker.search.placeholder") }
    static var placePickerSearchSection: String { string("place.picker.search.section") }
    static var placePickerSearchEmpty: String { string("place.picker.search.empty") }
    static var placePickerSearchHint: String { string("place.picker.search.hint") }
    static var placePickerSearchLoading: String { string("place.picker.search.loading") }
    static var placePickerSearchClear: String { string("place.picker.search.clear") }
    static var placePickerUseAddressAsName: String { string("place.picker.use_address_as_name") }
    static var placePickerEditTitle: String { string("place.picker.edit_title") }
    static var placePickerNewTitle: String { string("place.picker.new_title") }
    static var placePickerSave: String { string("place.picker.save") }
    static var placePrivacyZoneHint: String { string("place.privacy_zone.hint") }
    static var settingsPlacesSection: String { string("settings.places.section") }
    static var settingsPlacesSubtitle: String { string("settings.places.subtitle") }
    static var settingsFavoritePlaces: String { string("settings.favorite_places") }
    static var settingsFavoritePlacesHint: String { string("settings.favorite_places.hint") }
    static var settingsFavoritePlacesEmpty: String { string("settings.favorite_places.empty") }
    static var settingsAddPlace: String { string("settings.add_place") }

    static var actionRefresh: String { string("action.refresh") }
    static var settingsTitle: String { string("settings.title") }
    static var settingsVehiclePairingSection: String { string("settings.vehicle_pairing.section") }
    static var settingsPairedVehicle: String { string("settings.vehicle_pairing.paired") }
    static var settingsConnectionType: String { string("settings.vehicle_pairing.type") }
    static var settingsConnectionStatus: String { string("settings.vehicle_pairing.connection") }
    static var settingsConnected: String { string("settings.connection.connected") }
    static var settingsDisconnected: String { string("settings.connection.disconnected") }
    static var settingsChangeVehicle: String { string("settings.vehicle_pairing.change") }
    static var settingsRemovePairing: String { string("settings.vehicle_pairing.remove") }
    static var settingsPairVehicleHint: String { string("settings.vehicle_pairing.hint") }
    static var settingsDefineVehicle: String { string("settings.vehicle_pairing.define") }
    static var settingsAppearanceSection: String { string("settings.appearance.section") }
    static var settingsAppearanceHint: String { string("settings.appearance.hint") }
    static var settingsAppearanceSubtitle: String { string("settings.appearance.subtitle") }
    static var settingsAppearancePreviewTitle: String { string("settings.appearance.preview.title") }
    static var settingsAppearancePreviewDetail: String { string("settings.appearance.preview.detail") }
    static var settingsShellPaletteHint: String { string("settings.shell_palette.hint") }
    static var settingsPersonalizationSection: String { string("settings.personalization.section") }
    static var settingsThemeLightTitle: String { string("settings.theme.light.title") }
    static var settingsThemeDarkTitle: String { string("settings.theme.dark.title") }
    static var settingsThemeLightHint: String { string("settings.theme.light.hint") }
    static var settingsThemeDarkHint: String { string("settings.theme.dark.hint") }
    static var settingsThemeMatchSystem: String { string("settings.theme.match_system") }
    static var settingsTextSizeTitle: String { string("settings.text_size.title") }
    static var settingsLanguageSystem: String { string("settings.language.system") }

    static func settingsLanguageSystemSubtitle(_ name: String) -> String {
        String(format: string("settings.language.subtitle"), name)
    }

    static func shellPaletteName(_ palette: ShellPalette) -> String {
        string("settings.shell_palette.\(palette.rawValue)")
    }
    static var settingsSmartCategorySection: String { string("settings.smart_category.section") }
    static var settingsSmartCategoryToggle: String { string("settings.smart_category.toggle") }
    static var settingsSmartCategoryHint: String { string("settings.smart_category.hint") }
    static var settingsSmartCategoryWorkStart: String { string("settings.smart_category.work_start") }
    static var settingsSmartCategoryWorkEnd: String { string("settings.smart_category.work_end") }
    static var settingsLanguageSection: String { string("settings.language.section") }
    static var settingsFuelSection: String { string("settings.fuel.section") }
    static var settingsFuelConsumption: String { string("settings.fuel.consumption") }
    static var settingsFuelPrice: String { string("settings.fuel.price") }
    static var settingsFuelCurrency: String { string("settings.fuel.currency") }
    static var settingsFuelHint: String { string("settings.fuel.hint") }
    static var settingsPrivacySection: String { string("settings.privacy.section") }
    static var settingsAppLock: String { string("settings.privacy.app_lock") }
    static var settingsPrivacyRadius: String { string("settings.privacy.radius") }
    static var settingsBlurExport: String { string("settings.privacy.blur_export") }
    static var settingsAutoDelete: String { string("settings.privacy.auto_delete") }
    static var settingsAutoDeleteNever: String { string("settings.privacy.auto_delete.never") }
    static var settingsPermissionsSection: String { string("settings.permissions.section") }
    static var settingsLocationPermission: String { string("settings.permissions.location") }
    static var settingsNotificationsPermission: String { string("settings.permissions.notifications") }
    static var settingsPermissionGranted: String { string("settings.permissions.granted") }
    static var settingsPermissionRequired: String { string("settings.permissions.required") }
    static var settingsRequestLocationPermission: String { string("settings.permissions.request_location") }
    static var settingsRequestNotificationsPermission: String { string("settings.permissions.request_notifications") }
    static var settingsOpenSystemSettings: String { string("settings.permissions.open_settings") }
    static var settingsBackgroundLocationHint: String { string("settings.permissions.background_location_hint") }
    static var notificationsBadgeAllowed: String { string("notifications.badge.allowed") }
    static var notificationsBadgeDenied: String { string("notifications.badge.denied") }
    static var notificationsBadgeAsk: String { string("notifications.badge.ask") }

    static func achievementTitle(_ id: AchievementID) -> String {
        string(id.titleKey)
    }

    static func achievementsUnlockedCount(_ count: Int) -> String {
        String(format: string("premium.achievements.unlocked_count"), count)
    }

    static func recapNotificationTitle(_ year: Int) -> String {
        String(format: string("premium.recap.notification.title"), year)
    }
    static var settingsBackupSection: String { string("settings.backup.section") }
    static var settingsExportJSON: String { string("settings.backup.json") }
    static var settingsExportCSV: String { string("settings.backup.csv") }
    static var settingsExportGPX: String { string("settings.backup.gpx") }
    static var settingsExportKML: String { string("settings.backup.kml") }
    static var settingsExportPreparing: String { string("settings.backup.exporting") }
    static var settingsShareFile: String { string("settings.backup.share") }
    static var settingsAboutSection: String { string("settings.about.section") }
    static var settingsVersion: String { string("settings.about.version") }
    static var settingsAboutPrivacy: String { string("settings.about.privacy") }
    static var settingsReportProblem: String { string("settings.report_problem") }
    static var settingsReportProblemTitle: String { string("settings.report_problem.title") }
    static var settingsReportProblemDisclosure: String { string("settings.report_problem.disclosure") }
    static var settingsReportProblemOpenMail: String { string("settings.report_problem.open_mail") }
    static var settingsReportProblemClearLog: String { string("settings.report_problem.clear_log") }
    static var settingsReportProblemMailBody: String { string("settings.report_problem.mail_body") }
    static var settingsReportProblemFailedTitle: String { string("settings.report_problem.failed.title") }
    static var settingsReportProblemFailedMessage: String { string("settings.report_problem.failed.message") }
    static var settingsPrivacyPolicy: String { string("settings.privacy_policy") }
    static var settingsAcknowledgements: String { string("settings.acknowledgements") }
    static var settingsAcknowledgementsSounds: String { string("settings.acknowledgements.sounds") }
    static var settingsAcknowledgementsEdited: String { string("settings.acknowledgements.edited") }
    static var settingsAcknowledgementsFooter: String { string("settings.acknowledgements.footer") }
    static var drivingSafetyNoticeTitle: String { string("recording.safety_notice.title") }
    static var drivingSafetyNoticeMessage: String { string("recording.safety_notice.message") }
    static var drivingSafetyNoticeConfirm: String { string("recording.safety_notice.confirm") }
    static var settingsTipJar: String { string("settings.tip_jar") }
    static var settingsTipJarSubtitle: String { string("settings.tip_jar.subtitle") }
    static var settingsTipJarMessage: String { string("settings.tip_jar.message") }
    static var settingsTipJarUnavailable: String { string("settings.tip_jar.unavailable") }
    static var settingsTipJarFailed: String { string("settings.tip_jar.failed") }

    static func settingsDevelopedBy(_ name: String) -> String {
        String(format: string("settings.developed_by"), name)
    }

    static func settingsReportProblemShareHint(_ address: String) -> String {
        String(format: string("settings.report_problem.share_hint"), address)
    }
    static var settingsLocationNotDetermined: String { string("settings.location.not_determined") }
    static var settingsLocationWhenInUse: String { string("settings.location.when_in_use") }
    static var settingsLocationAlways: String { string("settings.location.always") }
    static var settingsLocationDenied: String { string("settings.location.denied") }
    static var settingsLocationRestricted: String { string("settings.location.restricted") }
    static var vehiclePairingTitle: String { string("vehicle.pairing.title") }
    static var vehiclePairingMessage: String { string("vehicle.pairing.message") }
    static var vehiclePairingConnectionType: String { string("vehicle.pairing.connection_type") }
    static var vehiclePairingBluetooth: String { string("vehicle.pairing.bluetooth") }
    static var vehiclePairingSkip: String { string("vehicle.pairing.skip") }
    static var vehiclePairingSavedVehicles: String { string("vehicle.pairing.saved_vehicles") }
    static var vehiclePairingConnectedDevice: String { string("vehicle.pairing.connected_device") }
    static var vehiclePairingConfirm: String { string("vehicle.pairing.confirm") }
    static var vehiclePairingBluetoothSetupHint: String { string("vehicle.pairing.bluetooth_setup_hint") }
    static var vehiclePairingWaitingBluetooth: String { string("vehicle.pairing.waiting_bluetooth") }
    static var vehiclePairingNoConnection: String { string("vehicle.pairing.no_connection") }
    static var vehiclePairingMissingConnection: String { string("vehicle.pairing.missing_connection") }
    static var vehicleDefaultName: String { string("vehicle.default_name") }
    static var vehicleAutoTrigger: String { string("vehicle.auto_trigger") }
    static var tripListSetupVehicleTitle: String { string("trip.list.setup_vehicle.title") }
    static var tripListSetupVehicleMessage: String { string("trip.list.setup_vehicle.message") }
    static var appLockReason: String { string("settings.privacy.app_lock_reason") }
    static var settingsConfirmExternalStart: String { string("settings.privacy.confirm_external_start") }
    static var appLockTitle: String { string("settings.privacy.app_lock_title") }
    static var appLockUnlock: String { string("settings.privacy.app_lock_unlock") }
    static var appLockUnavailableTitle: String { string("settings.privacy.app_lock_unavailable_title") }
    static var appLockUnavailable: String { string("settings.privacy.app_lock_unavailable") }
    static var externalStartConfirmTitle: String { string("recording.external_start.title") }
    static var externalStartConfirmMessage: String { string("recording.external_start.message") }
    static var externalStartConfirmAction: String { string("recording.external_start.confirm") }
    static var cancel: String { string("action.cancel") }
    static var deleteConfirmTitle: String { string("delete.confirm.title") }
    static var deleteConfirmMessage: String { string("delete.confirm.message") }
    static var deleteConfirmCategoryMessage: String { string("delete.confirm.category.message") }
    static var deleteConfirmJournalRemoveTitle: String { string("delete.confirm.journal.remove.title") }
    static var deleteConfirmJournalRemoveMessage: String { string("delete.confirm.journal.remove.message") }
    static var deleteConfirmInstallmentPlanMessage: String { string("delete.confirm.installment_plan.message") }
    static var deleteConfirmNotificationsAllMessage: String { string("delete.confirm.notifications.all.message") }
    static var vehicleExpenseDeletePlanTitle: String { string("vehicles.care.expense.delete_plan_title") }

    static func vehicleExpenseDeletePlan(_ count: Int) -> String {
        String(format: string("vehicles.care.expense.delete_plan"), count)
    }

    static var ok: String { string("action.ok") }
    static var settingsSiriShortcutsHint: String { string("settings.siri.shortcuts_hint") }
    static var settingsSiriShortcutsLink: String { string("settings.siri.shortcuts_link") }
    static var tabTrips: String { string("tab.trips") }
    static var tabStats: String { string("tab.stats") }
    static var tabYear: String { string("tab.year") }
    static var tabPairing: String { string("tab.pairing") }
    static var tabSettings: String { string("tab.settings") }

    static var pairingTabTitle: String { string("pairing.tab.title") }
    static var pairingTabHeroTitle: String { string("pairing.tab.hero.title") }
    static var pairingTabStatusConnected: String { string("pairing.tab.status.connected") }
    static var pairingTabStatusDisconnected: String { string("pairing.tab.status.disconnected") }
    static var pairingTabRefreshing: String { string("pairing.tab.refreshing") }
    static var pairingTabRefreshUpdated: String { string("pairing.tab.refresh.updated") }
    static var pairingTabRemovePairing: String { string("pairing.tab.remove_pairing") }
    static var pairingTabDeleteVehicleTitle: String { string("pairing.tab.delete_vehicle.title") }
    static var pairingTabDeleteVehicleMessage: String { string("pairing.tab.delete_vehicle.message") }
    static var pairingTabDeleteVehicleMessageActive: String { string("pairing.tab.delete_vehicle.message_active") }
    static var pairingTabAddVehicle: String { string("pairing.tab.add_vehicle") }
    static var pairingTabAddFirstVehicle: String { string("pairing.tab.add_first_vehicle") }
    static var pairingTabSavedVehicles: String { string("pairing.tab.saved_vehicles") }
    static var pairingTabActivePairing: String { string("pairing.tab.active_pairing") }
    static var pairingTabActiveBadge: String { string("pairing.tab.active_badge") }
    static var pairingTabSetupTitle: String { string("pairing.tab.setup.title") }
    static var pairingTabSetupSubtitle: String { string("pairing.tab.setup.subtitle") }
    static var pairingTabSelectVehicle: String { string("pairing.tab.select_vehicle") }
    static var pairingTabBluetoothSetupTitle: String { string("pairing.tab.bluetooth_setup.title") }
    static var pairingShortcutsGuideTitle: String { string("pairing.shortcuts.guide.title") }
    static var pairingShortcutsGuideIntro: String { string("pairing.shortcuts.guide.intro") }
    static var pairingShortcutsGuideCardTitle: String { string("pairing.shortcuts.guide.card.title") }
    static var pairingShortcutsGuideCardSubtitle: String { string("pairing.shortcuts.guide.card.subtitle") }
    static var pairingShortcutsGuideCardButton: String { string("pairing.shortcuts.guide.card.button") }
    static var pairingShortcutsGuidePrerequisiteTitle: String { string("pairing.shortcuts.guide.prerequisite.title") }
    static var pairingShortcutsGuidePrerequisiteBody: String { string("pairing.shortcuts.guide.prerequisite.body") }
    static var pairingShortcutsGuideSilentStart: String { string("pairing.shortcuts.guide.silent_start") }
    static var pairingShortcutsGuideTriggersTitle: String { string("pairing.shortcuts.guide.triggers.title") }
    static var pairingShortcutsGuideTriggersIntro: String { string("pairing.shortcuts.guide.triggers.intro") }
    static var pairingShortcutsGuideTriggersBluetoothTitle: String { string("pairing.shortcuts.guide.triggers.bluetooth.title") }
    static var pairingShortcutsGuideTriggersBluetoothBody: String { string("pairing.shortcuts.guide.triggers.bluetooth.body") }
    static var pairingShortcutsGuideTriggersCarPlayTitle: String { string("pairing.shortcuts.guide.triggers.carplay.title") }
    static var pairingShortcutsGuideTriggersCarPlayBody: String { string("pairing.shortcuts.guide.triggers.carplay.body") }
    static var pairingShortcutsGuideTriggersWiFiTitle: String { string("pairing.shortcuts.guide.triggers.wifi.title") }
    static var pairingShortcutsGuideTriggersWiFiBody: String { string("pairing.shortcuts.guide.triggers.wifi.body") }
    static var pairingShortcutsGuideConnectTitle: String { string("pairing.shortcuts.guide.connect.title") }
    static var pairingShortcutsGuideConnectStep1: String { string("pairing.shortcuts.guide.connect.step1") }
    static var pairingShortcutsGuideConnectStep2: String { string("pairing.shortcuts.guide.connect.step2") }
    static var pairingShortcutsGuideConnectStep3: String { string("pairing.shortcuts.guide.connect.step3") }
    static var pairingShortcutsGuideConnectStep4: String { string("pairing.shortcuts.guide.connect.step4") }
    static var pairingShortcutsGuideConnectStep5: String { string("pairing.shortcuts.guide.connect.step5") }
    static var pairingShortcutsGuideConnectStep6: String { string("pairing.shortcuts.guide.connect.step6") }
    static var pairingShortcutsGuideConnectStep7: String { string("pairing.shortcuts.guide.connect.step7") }
    static var pairingShortcutsGuideDisconnectTitle: String { string("pairing.shortcuts.guide.disconnect.title") }
    static var pairingShortcutsGuideDisconnectStep1: String { string("pairing.shortcuts.guide.disconnect.step1") }
    static var pairingShortcutsGuideDisconnectStep2: String { string("pairing.shortcuts.guide.disconnect.step2") }
    static var pairingShortcutsGuideDisconnectStep3: String { string("pairing.shortcuts.guide.disconnect.step3") }
    static var pairingShortcutsGuideDisconnectStep4: String { string("pairing.shortcuts.guide.disconnect.step4") }
    static var pairingShortcutsGuideNote: String { string("pairing.shortcuts.guide.note") }
    static var pairingShortcutsGuideOpenShortcuts: String { string("pairing.shortcuts.guide.open_shortcuts") }
    static var pairingShortcutsGuideDone: String { string("pairing.shortcuts.guide.done") }
    static var pairingShortcutsGuideNext: String { string("pairing.shortcuts.guide.next") }
    static var pairingShortcutsGuideBack: String { string("pairing.shortcuts.guide.back") }
    static var pairingShortcutsGuideHandoffTitle: String { string("pairing.shortcuts.guide.handoff.title") }
    static var pairingShortcutsGuideHandoffBody: String { string("pairing.shortcuts.guide.handoff.body") }
    static var pairingShortcutsGuideFinishedToggle: String { string("pairing.shortcuts.guide.finished.toggle") }
    static func pairingShortcutsGuideStepProgress(current: Int, total: Int) -> String {
        String(format: string("pairing.shortcuts.guide.step_progress"), current, total)
    }
    static var pairingShortcutsGuideTriggersCarPlayWirelessNote: String {
        string("pairing.shortcuts.guide.triggers.carplay.wireless_note")
    }
    static var pairingShortcutsGuideVehicleTitle: String { string("pairing.shortcuts.guide.vehicle.title") }
    static var pairingShortcutsGuideVehicleBody: String { string("pairing.shortcuts.guide.vehicle.body") }
    static var pairingShortcutsGuideVehicleEmpty: String { string("pairing.shortcuts.guide.vehicle.empty") }
    static var pairingShortcutsGuideVehicleAdd: String { string("pairing.shortcuts.guide.vehicle.add") }
    static var pairingShortcutsGuideVehicleNote: String { string("pairing.shortcuts.guide.vehicle.note") }
    static var pairingShortcutsGuideConnectStep5Bluetooth: String {
        string("pairing.shortcuts.guide.connect.step5.bluetooth")
    }
    static var pairingShortcutsGuideConnectStep5CarPlay: String {
        string("pairing.shortcuts.guide.connect.step5.carplay")
    }
    static var pairingShortcutsGuideConnectStep5WiFi: String {
        string("pairing.shortcuts.guide.connect.step5.wifi")
    }
    static var pairingShortcutsGuideCardTest: String { string("pairing.shortcuts.guide.card.test") }
    static var pairingShortcutsGuideCardTroubleshoot: String { string("pairing.shortcuts.guide.card.troubleshoot") }
    static var pairingShortcutsGuideCardTested: String { string("pairing.shortcuts.guide.card.tested") }
    static var pairingShortcutsGuideTestTitle: String { string("pairing.shortcuts.guide.test.title") }
    static var pairingShortcutsGuideTestBody: String { string("pairing.shortcuts.guide.test.body") }
    static var pairingShortcutsGuideTestButton: String { string("pairing.shortcuts.guide.test.button") }
    static var pairingShortcutsGuideTestStop: String { string("pairing.shortcuts.guide.test.stop") }
    static var pairingShortcutsGuideTestWatch: String { string("pairing.shortcuts.guide.test.watch") }
    static var pairingShortcutsGuideTestWatchArmed: String { string("pairing.shortcuts.guide.test.watch.armed") }
    static var pairingShortcutsGuideTestResultStarted: String { string("pairing.shortcuts.guide.test.result.started") }
    static var pairingShortcutsGuideTestResultConfirm: String { string("pairing.shortcuts.guide.test.result.confirm") }
    static var pairingShortcutsGuideTestResultNoLocation: String {
        string("pairing.shortcuts.guide.test.result.no_location")
    }
    static var pairingShortcutsGuideTestResultNoVehicle: String {
        string("pairing.shortcuts.guide.test.result.no_vehicle")
    }
    static var pairingShortcutsGuideTestResultIdle: String { string("pairing.shortcuts.guide.test.result.idle") }
    static var pairingShortcutsGuideChecklistTitle: String { string("pairing.shortcuts.guide.checklist.title") }
    static var pairingShortcutsGuideChecklistIntro: String { string("pairing.shortcuts.guide.checklist.intro") }
    static var pairingShortcutsGuideChecklistPersonalAutomation: String {
        string("pairing.shortcuts.guide.checklist.personal_automation")
    }
    static var pairingShortcutsGuideChecklistAskBeforeRunning: String {
        string("pairing.shortcuts.guide.checklist.ask_before_running")
    }
    static var pairingShortcutsGuideChecklistRunShortcut: String {
        string("pairing.shortcuts.guide.checklist.run_shortcut")
    }
    static var pairingShortcutsGuideChecklistSecondVehicle: String {
        string("pairing.shortcuts.guide.checklist.second_vehicle")
    }
    static var pairingShortcutsGuideChecklistLocationAlways: String {
        string("pairing.shortcuts.guide.checklist.location_always")
    }
    static var pairingShortcutsGuideChecklistSilentStart: String {
        string("pairing.shortcuts.guide.checklist.silent_start")
    }
    static var pairingShortcutsGuideChecklistCarPlayWireless: String {
        string("pairing.shortcuts.guide.checklist.carplay_wireless")
    }
    static var pairingShortcutsGuideChecklistFocus: String { string("pairing.shortcuts.guide.checklist.focus") }
    static var pairingShortcutsGuideChecklistReturnLink: String {
        string("pairing.shortcuts.guide.checklist.return_link")
    }
    static var toastShortcutsGuideFinished: String { string("toast.shortcuts.guide.finished") }
    static var toastShortcutsAutomationReached: String { string("toast.shortcuts.automation.reached") }
    static var settingsShortcutsAutomationGuide: String { string("settings.shortcuts.automation_guide") }
    static var shortcutStartTitle: String { string("shortcut.start.title") }
    static var shortcutStopTitle: String { string("shortcut.stop.title") }
    static var pairingTabRecordingStatus: String { string("pairing.tab.recording_status") }
    static var pairingReadinessTitle: String { string("pairing.tab.readiness.title") }
    static var pairingReadinessLocationAlways: String { string("pairing.tab.readiness.location_always") }
    static var pairingReadinessVehiclePaired: String { string("pairing.tab.readiness.vehicle_paired") }
    static var pairingReadinessConnectionDetected: String { string("pairing.tab.readiness.connection_detected") }
    static var pairingTabDefineVehicle: String { string("pairing.tab.define_vehicle") }
    static var pairingTabConnectionNow: String { string("pairing.tab.connection_now") }
    static var pairingTabConnectionDetected: String { string("pairing.tab.connection_detected") }
    static var pairingTabConnectionNotDetected: String { string("pairing.tab.connection_not_detected") }
    static var pairingTabPairNow: String { string("pairing.tab.pair_now") }
    static var pairingTabPairedSuccess: String { string("pairing.tab.paired_success") }
    static var pairingTabWaitingConnection: String { string("pairing.tab.wait_connection") }
    static var pairingSuggestionTitle: String { string("pairing.suggestion.title") }
    static var pairingSuggestionBody: String { string("pairing.suggestion.body") }
    static var pairingTabConfirmVehicleHint: String { string("pairing.tab.confirm_vehicle_hint") }
    static var pairingTabAdvanced: String { string("pairing.tab.advanced") }
    static var pairingTabPickChannelHint: String { string("pairing.tab.pick_channel_hint") }
    static func pairingTabDebugDevice(_ device: String) -> String {
        String(format: string("pairing.tab.debug.device"), device)
    }
    static func pairingTabDebugUID(_ uid: String) -> String {
        String(format: string("pairing.tab.debug.uid"), uid)
    }
    static func pairingTabDebugMatchMethod(_ method: String) -> String {
        String(format: string("pairing.tab.debug.match_method"), method)
    }
    static var pairingTabDebugMatchUID: String { string("pairing.tab.debug.match.uid") }
    static var pairingTabDebugMatchName: String { string("pairing.tab.debug.match.name") }
    static var pairingTabDebugMatchLegacy: String { string("pairing.tab.debug.match.legacy") }
    static var pairingTabDebugMatchLastKnown: String { string("pairing.tab.debug.match.last_known") }
    static var pairingTabFirstSetupHint: String { string("pairing.tab.first_setup_hint") }
    static var pairingTabEmptyTitle: String { string("pairing.tab.empty.title") }
    static var pairingTabEmptyMessage: String { string("pairing.tab.empty.message") }
    static var pairingTabVehicleSection: String { string("pairing.tab.vehicle.section") }
    static var pairingTabVehicleName: String { string("pairing.tab.vehicle.name") }
    static var pairingTabVehicleIcon: String { string("pairing.tab.vehicle.icon") }
    static var pairingTabVehiclePhoto: String { string("pairing.tab.vehicle.photo") }
    static var pairingTabVehiclePhotoChange: String { string("pairing.tab.vehicle.photo.change") }
    static var pairingTabVehiclePhotoAdjust: String { string("pairing.tab.vehicle.photo.adjust") }
    static var pairingTabVehiclePhotoActionDelete: String { string("pairing.tab.vehicle.photo.action.delete") }
    static var pairingTabVehiclePhotoActionChange: String { string("pairing.tab.vehicle.photo.action.change") }
    static var pairingTabVehiclePhotoActionEdit: String { string("pairing.tab.vehicle.photo.action.edit") }
    static var pairingTabVehiclePhotoActionAdd: String { string("pairing.tab.vehicle.photo.action.add") }
    static var pairingTabVehiclePhotoTapHint: String { string("pairing.tab.vehicle.photo.tap_hint") }
    static var pairingTabVehiclePhotoChoose: String { string("pairing.tab.vehicle.photo.choose") }
    static var pairingTabVehiclePhotoChooseSubtitle: String { string("pairing.tab.vehicle.photo.choose.subtitle") }
    static var pairingTabVehiclePhotoCamera: String { string("pairing.tab.vehicle.photo.camera") }
    static var pairingTabVehiclePhotoCameraSubtitle: String { string("pairing.tab.vehicle.photo.camera.subtitle") }
    static var pairingTabVehiclePhotoRemove: String { string("pairing.tab.vehicle.photo.remove") }
    static var pairingTabVehiclePhotoFailed: String { string("pairing.tab.vehicle.photo.failed") }
    static var pairingTabVehiclePhotoSourceSubtitle: String { string("pairing.tab.vehicle.photo.source.subtitle") }
    static var pairingTabVehiclePhotoCropTitle: String { string("pairing.tab.vehicle.photo.crop.title") }
    static var pairingTabVehiclePhotoCropHint: String { string("pairing.tab.vehicle.photo.crop.hint") }
    static var pairingTabVehiclePhotoUse: String { string("pairing.tab.vehicle.photo.use") }
    static var pairingTabVehiclePhotoApply: String { string("pairing.tab.vehicle.photo.apply") }
    static var pairingTabVehiclePhotoDeleteTitle: String { string("pairing.tab.vehicle.photo.delete.title") }
    static var pairingTabVehiclePhotoDeleteMessage: String { string("pairing.tab.vehicle.photo.delete.message") }
    static var pairingTabVehiclePhotoZoom: String { string("pairing.tab.vehicle.photo.zoom") }
    static var pairingTabVehiclePhotoOrientation: String { string("pairing.tab.vehicle.photo.orientation") }
    static var pairingTabVehiclePhotoRotateLeft: String { string("pairing.tab.vehicle.photo.rotate.left") }
    static var pairingTabVehiclePhotoRotateRight: String { string("pairing.tab.vehicle.photo.rotate.right") }
    static var pairingTabVehiclePhotoFlipHorizontal: String { string("pairing.tab.vehicle.photo.flip.horizontal") }
    static var pairingTabVehiclePhotoFlipVertical: String { string("pairing.tab.vehicle.photo.flip.vertical") }
    static var pairingTabVehiclePhotoPreviewList: String { string("pairing.tab.vehicle.photo.preview.list") }
    static var pairingTabVehiclePhotoPreviewEditor: String { string("pairing.tab.vehicle.photo.preview.editor") }
    static var pairingTabVehiclePhotoAllPhotos: String { string("pairing.tab.vehicle.photo.all_photos") }
    static var pairingTabVehiclePhotoShutter: String { string("pairing.tab.vehicle.photo.shutter") }
    static var pairingTabVehiclePhotoMore: String { string("pairing.tab.vehicle.photo.more") }
    static var pairingTabVehiclePhotoLibraryEmpty: String { string("pairing.tab.vehicle.photo.library.empty") }
    static var pairingTabVehiclePhotoLibraryDeniedTitle: String { string("pairing.tab.vehicle.photo.library.denied.title") }
    static var pairingTabVehiclePhotoLibraryDeniedMessage: String { string("pairing.tab.vehicle.photo.library.denied.message") }
    static var pairingTabVehiclePhotoCameraDeniedTitle: String { string("pairing.tab.vehicle.photo.camera.denied.title") }
    static var pairingTabVehiclePhotoCameraDeniedMessage: String { string("pairing.tab.vehicle.photo.camera.denied.message") }
    static var pairingTabVehiclePhotoOpenSettings: String { string("pairing.tab.vehicle.photo.open_settings") }
    static var pairingTabVehicleNotFound: String { string("pairing.tab.vehicle.not_found") }
    static var pairingTabFuelType: String { string("pairing.tab.vehicle.fuel_type") }
    static var pairingTabChargePrice: String { string("pairing.tab.vehicle.charge_price") }
    static var pairingTabDefaultVehicle: String { string("pairing.tab.vehicle.default") }
    static var pairingTabSave: String { string("pairing.tab.save") }
    static var pairingTabDiscardVehicleEditsTitle: String { string("pairing.tab.discard_edits.title") }
    static var pairingTabDiscardVehicleEditsMessage: String { string("pairing.tab.discard_edits.message") }
    static var pairingTabDiscardVehicleEditsLeave: String { string("pairing.tab.discard_edits.leave") }
    static var pairingTabNewVehicleName: String { string("pairing.tab.new_vehicle_name") }
    static var pairingTabMissingConnection: String { string("pairing.tab.missing_connection") }
    static var pairingTabWaitingBluetooth: String { string("pairing.tab.waiting_bluetooth") }
    static var pairingLiveConnectionTitle: String { string("pairing.live_connection.title") }
    static var pairingLiveConnectionNone: String { string("pairing.live_connection.none") }
    static func pairingConnectionBluetooth(_ name: String, _ portType: String) -> String {
        String(format: string("pairing.connection.bluetooth"), name, portType)
    }

    static var orphanBannerTitle: String { string("orphan.banner.title") }
    static var orphanBannerMessage: String { string("orphan.banner.message") }
    static var orphanResume: String { string("orphan.banner.resume") }
    static var orphanSave: String { string("orphan.banner.save") }
    static var orphanAlreadyEnded: String { string("orphan.error.already_ended") }
    static var orphanResumeBusy: String { string("orphan.error.resume_busy") }
    static var orphanResumeFailed: String { string("orphan.error.resume_failed") }

    static func orphanSaveFailed(_ detail: String) -> String {
        String(format: string("orphan.error.save_failed"), detail)
    }

    static func orphanDeleteFailed(_ detail: String) -> String {
        String(format: string("orphan.error.delete_failed"), detail)
    }

    static func storeOpenFailed(_ detail: String) -> String {
        String(format: string("store.open_failed"), detail)
    }

    static var storeRecoveredAfterReset: String { string("store.recovered_after_reset") }
    static var storeOpenFailedInMemory: String { string("store.open_failed_in_memory") }
    static var errorTitle: String { string("alert.error.title") }
    static var infoTitle: String { string("alert.info.title") }

    static var toastSaved: String { string("toast.saved") }
    static var toastTipThanks: String { string("toast.tip_thanks") }
    static var toastDeleted: String { string("toast.deleted") }
    static var toastPlaceSaved: String { string("toast.place.saved") }
    static var toastVehicleSaved: String { string("toast.vehicle.saved") }
    static var toastVehicleReminderSaved: String { string("toast.vehicle.reminder.saved") }
    static var toastVehicleExpenseSaved: String { string("toast.vehicle.expense.saved") }
    static var toastTripSaved: String { string("toast.trip.saved") }
    static var toastTripNotFound: String { string("toast.trip.not_found") }
    static var toastJournalSaved: String { string("toast.journal.saved") }
    static var toastCategoryAdded: String { string("toast.category.added") }
    static var toastCategoryDeleted: String { string("toast.category.deleted") }
    static var toastCategoryAccepted: String { string("toast.category.accepted") }
    static var toastOrphanSaved: String { string("toast.orphan.saved") }
    static var toastTripsMerged: String { string("toast.trips.merged") }
    static var toastRecordKicker: String { string("toast.record.kicker") }

    static func toastRecordLongest(_ distance: String) -> String {
        String(format: string("toast.record.longest"), distance)
    }

    static func toastRecordFastest(_ speed: String) -> String {
        String(format: string("toast.record.fastest"), speed)
    }

    static func pairingTabSaveFailed(_ detail: String) -> String {
        String(format: string("pairing.tab.save_failed"), detail)
    }

    static func pairingTabDeleteFailed(_ detail: String) -> String {
        String(format: string("pairing.tab.delete_failed"), detail)
    }

    static func placeSuggestionVisits(_ count: Int) -> String {
        let format = string("place.suggestion.visits")
        return String(format: format, count)
    }

    /// Trip-list strip. The numbers are a rolling 7×24 hours, not the calendar week.
    static var lastSevenDays: String { string("trips.last_seven_days") }

    static func weekSummary(distance: String, duration: String) -> String {
        let format = string("week.summary")
        return String(format: format, distance, duration)
    }

    static func formatSpeedKmh(_ kmh: Double) -> String {
        String(format: "%.0f %@", kmh, speedKmh)
    }

    static func maxSpeedDetail(_ speed: String) -> String {
        let format = string("trip.max_speed_detail")
        return String(format: format, speed)
    }

    static var locationBadgeAlways: String { string("location.badge.always") }
    static var locationBadgeWhenInUse: String { string("location.badge.when_in_use") }
    static var locationBadgeDenied: String { string("location.badge.denied") }
    static var pairingLocationWarning: String { string("pairing.location.warning") }
    static var locationBannerGrant: String { string("location.banner.grant") }
    static var locationBannerSettings: String { string("location.banner.settings") }

    static var autoLogSectionTitle: String { string("auto_log.section.title") }
    static var autoLogSectionHint: String { string("auto_log.section.hint") }
    static var autoLogEmpty: String { string("auto_log.empty") }
    static var autoLogClear: String { string("auto_log.clear") }

    static func autoLogBluetoothConnectedStarted(_ time: String, _ vehicle: String?, _ delay: Int) -> String {
        String(format: string("auto_log.bt.connected.started"), time, vehicle ?? "—", delay)
    }

    static func autoLogBluetoothConnectedAwaitingGPS(_ time: String, _ vehicle: String?, _ delay: Int) -> String {
        String(format: string("auto_log.bt.connected.awaiting_gps"), time, vehicle ?? "—", delay)
    }

    static func autoLogBluetoothConnectedCancelled(_ time: String, _ vehicle: String?) -> String {
        String(format: string("auto_log.bt.connected.cancelled"), time, vehicle ?? "—")
    }

    static func autoLogBluetoothConnectedSkipped(_ time: String, _ vehicle: String?) -> String {
        String(format: string("auto_log.bt.connected.skipped"), time, vehicle ?? "—")
    }

    static func autoLogBluetoothDisconnectedStopped(_ time: String, _ delay: Int, _ distance: String) -> String {
        String(format: string("auto_log.bt.disconnected.stopped"), time, delay, distance)
    }

    static func autoLogBluetoothDisconnectedSkipped(_ time: String) -> String {
        String(format: string("auto_log.bt.disconnected.skipped"), time)
    }

    static func autoLogMotionStarted(_ time: String) -> String {
        String(format: string("auto_log.motion.started"), time)
    }

    static func autoLogMotionStopped(_ time: String, _ distance: String) -> String {
        String(format: string("auto_log.motion.stopped"), time, distance)
    }

    static var tripsSegmentTrips: String { string("trips.segment.trips") }
    static var tripsSegmentTravels: String { string("trips.segment.travels") }
    static var journalEmptyTitle: String { string("journal.empty.title") }
    static var journalEmptyMessage: String { string("journal.empty.message") }
    static var journalEmptySearchTitle: String { string("journal.empty.search.title") }
    static var journalEmptySearchMessage: String { string("journal.empty.search.message") }
    static var journalSuggestChip: String { string("journal.suggest.chip") }
    static var journalSuggestAccept: String { string("journal.suggest.accept") }
    static var journalSuggestDismiss: String { string("journal.suggest.dismiss") }
    static var journalAdd: String { string("journal.add") }
    static var journalAddHelpTitle: String { string("journal.add.help.title") }
    static var journalAddHelpBody: String { string("journal.add.help.body") }
    static var journalNew: String { string("journal.new") }
    static var journalRemove: String { string("journal.remove") }
    static var journalMove: String { string("journal.move") }
    static var journalSave: String { string("journal.save") }
    static var journalTitle: String { string("journal.title") }
    static var journalTitlePlaceholder: String { string("journal.title.placeholder") }
    static var journalTitleRequired: String { string("journal.title.required") }
    static var journalNote: String { string("journal.note") }
    static var journalNotePlaceholder: String { string("journal.note.placeholder") }
    static var journalTrips: String { string("journal.trips") }
    static var journalDelete: String { string("journal.delete") }
    static var journalStatsFilter: String { string("journal.stats.filter") }
    static var journalSearchPlaceholder: String { string("journal.search.placeholder") }
    static var journalCreate: String { string("journal.create") }
    static var journalNone: String { string("journal.none") }

    static func journalTripCount(_ count: Int) -> String {
        String(format: string("journal.trip_count"), count)
    }

    static func journalDateRange(start: Date, end: Date) -> String {
        let startText = DateFormatters.tripDateOnly.string(from: start)
        if Calendar.current.isDate(start, inSameDayAs: end) {
            return startText
        }
        return "\(startText) – \(DateFormatters.tripDateOnly.string(from: end))"
    }
}
