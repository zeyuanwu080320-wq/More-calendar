#!/usr/bin/env python3
"""Generate the app-only Xcode project used for the local release.

The release source tree no longer contains XCTest fixtures or tests. This script
keeps the Xcode project aligned with that cleanup: one application target, no
stale test file references.
"""
from __future__ import annotations

import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROJECT_NAME = "SchoolEventInbox"
PROJECT_DIR = ROOT / f"{PROJECT_NAME}.xcodeproj"


def oid(key: str) -> str:
    return hashlib.md5(key.encode("utf-8")).hexdigest()[:24].upper()


def q(value: str) -> str:
    safe = all(ch.isalnum() or ch in "._/$()+-" for ch in value)
    if safe and not value.startswith("$"):
        return value
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


APP_FILES = [
    "SchoolEventInboxApp.swift",
    "AppModel.swift",
    "ImageSupport.swift",
    "PromptLoader.swift",
    "LanguageManager.swift",
    "AppDelegate.swift",
]
APP_VIEWS = [
    "ContentView.swift",
    "InputPane.swift",
    "EventListPane.swift",
    "EventCard.swift",
    "FooterBar.swift",
    "APIKeySheet.swift",
    "ManagedEventsView.swift",
]
CORE_MODELS = ["EventType.swift", "ParsedEvent.swift", "EventDraft.swift", "ManagedEvent.swift", "InputSource.swift"]
CORE_SERVICES = [
    "DeepSeekService.swift",
    "OCRService.swift",
    "KeychainService.swift",
    "LogService.swift",
]
CORE_PROVIDERS = [
    "TargetProvider.swift",
    "ManagedEventMetadata.swift",
    "AppleCalendarProvider.swift",
    "AppleRemindersProvider.swift",
]
CORE_UTILITIES = ["FlexibleDateParser.swift"]


def build_file(key: str, ref: str) -> str:
    return f"{oid('buildfile:' + key)} /* {key} in Build */ = {{isa = PBXBuildFile; fileRef = {ref}; }};"


def file_ref(key: str, path: str, file_type: str) -> str:
    return (
        f"{oid('fileref:' + key)} /* {path} */ = {{isa = PBXFileReference; "
        f"lastKnownFileType = {file_type}; path = {q(path)}; sourceTree = \"<group>\"; }};"
    )


def group(key: str, name: str, children: list[str], path: str | None = None) -> str:
    path_line = f"path = {q(path)}; " if path else ""
    return (
        f"{oid('group:' + key)} /* {name} */ = {{isa = PBXGroup; children = ({', '.join(children)}); "
        f"{path_line}sourceTree = \"<group>\"; }};"
    )


def main() -> None:
    PROJECT_DIR.mkdir(parents=True, exist_ok=True)
    (PROJECT_DIR / "xcshareddata" / "xcschemes").mkdir(parents=True, exist_ok=True)

    project_id = oid("project")
    target = oid("target:app")
    product = oid("product:app")
    sources_phase = oid("phase:app-sources")
    frameworks_phase = oid("phase:app-frameworks")
    resources_phase = oid("phase:app-resources")
    config_list = oid("configlist:project")
    target_config_list = oid("configlist:app")
    project_debug = oid("config:project:debug")
    project_release = oid("config:project:release")
    app_debug = oid("config:app:debug")
    app_release = oid("config:app:release")

    main_group = oid("group:main")
    products_group = oid("group:Products")
    sources_group = oid("group:Sources")
    app_group = oid("group:App")
    views_group = oid("group:Views")
    resources_group = oid("group:Resources")
    core_group = oid("group:Core")
    models_group = oid("group:Models")
    services_group = oid("group:Services")
    providers_group = oid("group:Providers")
    utilities_group = oid("group:Utilities")
    support_group = oid("group:Support")

    prompt_ref = oid("fileref:system_prompt.txt")
    localization_ref = oid("fileref:en.lproj")
    info_ref = oid("fileref:Info.plist")

    refs: list[str] = []
    build_lines: list[str] = []
    app_refs: list[str] = []
    view_refs: list[str] = []
    model_refs: list[str] = []
    service_refs: list[str] = []
    provider_refs: list[str] = []
    utility_refs: list[str] = []

    def add(key: str, path: str, bucket: list[str]) -> None:
        ref = oid("fileref:" + key)
        refs.append(file_ref(key, path, "sourcecode.swift"))
        build_lines.append(build_file(key, ref))
        bucket.append(ref)

    for name in APP_FILES:
        add(name, name, app_refs)
    for name in APP_VIEWS:
        add("Views/" + name, name, view_refs)
    for name in CORE_MODELS:
        add("Models/" + name, name, model_refs)
    for name in CORE_SERVICES:
        add("Services/" + name, name, service_refs)
    for name in CORE_PROVIDERS:
        add("Providers/" + name, name, provider_refs)
    for name in CORE_UTILITIES:
        add("Utilities/" + name, name, utility_refs)

    refs.extend([
        f"{prompt_ref} /* system_prompt.txt */ = {{isa = PBXFileReference; lastKnownFileType = text; path = system_prompt.txt; sourceTree = \"<group>\"; }};",
        f"{localization_ref} /* en.lproj */ = {{isa = PBXFileReference; lastKnownFileType = folder; path = en.lproj; sourceTree = \"<group>\"; }};",
        f"{info_ref} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = \"<group>\"; }};",
        f"{product} /* SchoolEventInbox.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = SchoolEventInbox.app; sourceTree = BUILT_PRODUCTS_DIR; }};",
    ])
    build_lines.append(build_file("system_prompt.txt", prompt_ref))
    build_lines.append(build_file("en.lproj", localization_ref))

    groups = [
        group("main", "Main", [sources_group, support_group, products_group]),
        group("Products", "Products", [product]),
        group("Sources", "Sources", [app_group, core_group], path="Sources"),
        group("App", "SchoolEventInbox", app_refs + [views_group, resources_group], path="SchoolEventInbox"),
        group("Views", "Views", view_refs, path="Views"),
        group("Resources", "Resources", [prompt_ref, localization_ref], path="Resources"),
        group("Core", "SchoolEventInboxCore", [models_group, services_group, providers_group, utilities_group], path="SchoolEventInboxCore"),
        group("Models", "Models", model_refs, path="Models"),
        group("Services", "Services", service_refs, path="Services"),
        group("Providers", "Providers", provider_refs, path="Providers"),
        group("Utilities", "Utilities", utility_refs, path="Utilities"),
        group("Support", "Support", [info_ref], path="Support"),
    ]

    source_build_refs = [
        oid("buildfile:" + name) for name in APP_FILES
    ] + [
        oid("buildfile:Views/" + name) for name in APP_VIEWS
    ] + [
        oid("buildfile:Models/" + name) for name in CORE_MODELS
    ] + [
        oid("buildfile:Services/" + name) for name in CORE_SERVICES
    ] + [
        oid("buildfile:Providers/" + name) for name in CORE_PROVIDERS
    ] + [
        oid("buildfile:Utilities/" + name) for name in CORE_UTILITIES
    ]

    common = """
                ALWAYS_SEARCH_USER_PATHS = NO;
                CLANG_ENABLE_MODULES = YES;
                CLANG_ENABLE_OBJC_ARC = YES;
                COPY_PHASE_STRIP = NO;
                DEAD_CODE_STRIPPING = YES;
                ENABLE_STRICT_OBJC_MSGSEND = YES;
                ENABLE_TESTABILITY = YES;
                GCC_C_LANGUAGE_STANDARD = gnu17;
                GCC_NO_COMMON_BLOCKS = YES;
                MACOSX_DEPLOYMENT_TARGET = 15.0;
                SDKROOT = macosx;
                SWIFT_VERSION = 5.0;
                ENABLE_USER_SCRIPT_SANDBOXING = NO;
"""
    project_debug_settings = common + """
                DEBUG_INFORMATION_FORMAT = dwarf;
                GCC_OPTIMIZATION_LEVEL = 0;
                GCC_PREPROCESSOR_DEFINITIONS = ("DEBUG=1", "$(inherited)");
                ONLY_ACTIVE_ARCH = YES;
                SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";
                SWIFT_OPTIMIZATION_LEVEL = "-Onone";
"""
    project_release_settings = common + """
                DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
                ENABLE_NS_ASSERTIONS = NO;
                SWIFT_COMPILATION_MODE = wholemodule;
                SWIFT_OPTIMIZATION_LEVEL = "-O";
"""
    app_settings = """
                CODE_SIGN_IDENTITY = "-";
                CODE_SIGN_STYLE = Manual;
                COMBINE_HIDPI_IMAGES = YES;
                CURRENT_PROJECT_VERSION = 1;
                DEVELOPMENT_TEAM = "";
                ENABLE_APP_SANDBOX = NO;
                ENABLE_HARDENED_RUNTIME = NO;
                GENERATE_INFOPLIST_FILE = NO;
                INFOPLIST_FILE = Support/Info.plist;
                LD_RUNPATH_SEARCH_PATHS = ("$(inherited)", "@executable_path/../Frameworks");
                MARKETING_VERSION = 0.1.0;
                PRODUCT_BUNDLE_IDENTIFIER = local.duishangque.SchoolEventInbox;
                PRODUCT_NAME = "$(TARGET_NAME)";
                SWIFT_EMIT_LOC_STRINGS = NO;
                SWIFT_VERSION = 5.0;
"""

    configs = [
        f"{project_debug} /* Debug */ = {{isa = XCBuildConfiguration; buildSettings = {{{project_debug_settings}}}; name = Debug; }};",
        f"{project_release} /* Release */ = {{isa = XCBuildConfiguration; buildSettings = {{{project_release_settings}}}; name = Release; }};",
        f"{app_debug} /* Debug */ = {{isa = XCBuildConfiguration; buildSettings = {{{app_settings}}}; name = Debug; }};",
        f"{app_release} /* Release */ = {{isa = XCBuildConfiguration; buildSettings = {{{app_settings}}}; name = Release; }};",
    ]
    config_lists = [
        f"{config_list} /* Build configuration list for PBXProject */ = {{isa = XCConfigurationList; buildConfigurations = ({project_debug}, {project_release}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }};",
        f"{target_config_list} /* Build configuration list for PBXNativeTarget */ = {{isa = XCConfigurationList; buildConfigurations = ({app_debug}, {app_release}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }};",
    ]

    app_target_obj = f"""{target} /* SchoolEventInbox */ = {{
            isa = PBXNativeTarget;
            buildConfigurationList = {target_config_list};
            buildPhases = ({sources_phase}, {frameworks_phase}, {resources_phase});
            buildRules = ();
            dependencies = ();
            name = SchoolEventInbox;
            productName = SchoolEventInbox;
            productReference = {product};
            productType = "com.apple.product-type.application";
        }};"""

    project_obj = f"""{project_id} /* Project object */ = {{
            isa = PBXProject;
            attributes = {{
                BuildIndependentTargetsInParallel = 1;
                LastSwiftUpdateCheck = 1600;
                LastUpgradeCheck = 1600;
                TargetAttributes = {{
                    {target} = {{CreatedOnToolsVersion = 16.0; }};
                }};
            }};
            buildConfigurationList = {config_list};
            compatibilityVersion = "Xcode 14.0";
            developmentRegion = "zh-Hans";
            hasScannedForEncodings = 0;
            knownRegions = (en, Base, "zh-Hans");
            mainGroup = {main_group};
            productRefGroup = {products_group};
            projectDirPath = "";
            projectRoot = "";
            targets = ({target});
        }};"""

    lines = [
        "// !$*UTF8*$!",
        "{",
        "\tarchiveVersion = 1;",
        "\tclasses = {};",
        "\tobjectVersion = 56;",
        "\tobjects = {",
        "",
        "/* Begin PBXBuildFile section */",
    ]
    lines += ["\t\t" + line for line in build_lines]
    lines += [
        "/* End PBXBuildFile section */",
        "",
        "/* Begin PBXFileReference section */",
    ]
    lines += ["\t\t" + line for line in refs]
    lines += [
        "/* End PBXFileReference section */",
        "",
        "/* Begin PBXFrameworksBuildPhase section */",
        f"\t\t{frameworks_phase} /* Frameworks */ = {{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0; }};",
        "/* End PBXFrameworksBuildPhase section */",
        "",
        "/* Begin PBXGroup section */",
    ]
    lines += ["\t\t" + line for line in groups]
    lines += [
        "/* End PBXGroup section */",
        "",
        "/* Begin PBXNativeTarget section */",
        "\t\t" + app_target_obj,
        "/* End PBXNativeTarget section */",
        "",
        "/* Begin PBXProject section */",
        "\t\t" + project_obj,
        "/* End PBXProject section */",
        "",
        "/* Begin PBXResourcesBuildPhase section */",
        f"\t\t{resources_phase} /* Resources */ = {{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({oid('buildfile:system_prompt.txt')}, {oid('buildfile:en.lproj')}); runOnlyForDeploymentPostprocessing = 0; }};",
        "/* End PBXResourcesBuildPhase section */",
        "",
        "/* Begin PBXSourcesBuildPhase section */",
        f"\t\t{sources_phase} /* Sources */ = {{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({', '.join(source_build_refs)}); runOnlyForDeploymentPostprocessing = 0; }};",
        "/* End PBXSourcesBuildPhase section */",
        "",
        "/* Begin XCBuildConfiguration section */",
    ]
    lines += ["\t\t" + line for line in configs]
    lines += [
        "/* End XCBuildConfiguration section */",
        "",
        "/* Begin XCConfigurationList section */",
    ]
    lines += ["\t\t" + line for line in config_lists]
    lines += [
        "/* End XCConfigurationList section */",
        "\t};",
        f"\trootObject = {project_id} /* Project object */;",
        "}",
    ]
    (PROJECT_DIR / "project.pbxproj").write_text("\n".join(lines) + "\n", encoding="utf-8")

    scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.7">
   <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
            <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="SchoolEventInbox.app" BlueprintName="SchoolEventInbox" ReferencedContainer="container:SchoolEventInbox.xcodeproj"/>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES">
      <Testables/>
   </TestAction>
   <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES">
      <BuildableProductRunnable runnableDebuggingMode="0">
         <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="SchoolEventInbox.app" BlueprintName="SchoolEventInbox" ReferencedContainer="container:SchoolEventInbox.xcodeproj"/>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES">
      <BuildableProductRunnable runnableDebuggingMode="0">
         <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="SchoolEventInbox.app" BlueprintName="SchoolEventInbox" ReferencedContainer="container:SchoolEventInbox.xcodeproj"/>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration="Debug"/>
   <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
'''
    (PROJECT_DIR / "xcshareddata" / "xcschemes" / f"{PROJECT_NAME}.xcscheme").write_text(scheme, encoding="utf-8")
    print(f"Generated {PROJECT_DIR}")
    print("Target: SchoolEventInbox (application only; no test target)")


if __name__ == "__main__":
    main()
