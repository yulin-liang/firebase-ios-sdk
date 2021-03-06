/*
 * Copyright 2019 Google
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import Foundation
import Utils

/// Describes an object that can check if a file eists in the filesystem. Used to allow for better
/// testing with FileManager.
protocol FileChecker {
  /// Returns a Boolean value that indicates whether a file or directory exists at a specified path.
  /// This matches the `FileManager` API.
  func fileExists(atPath: String) -> Bool

  /// Returns a Boolean value that indicates whether a directory exists at a specified path.
  func directoryExists(at url: URL) -> Bool
}

// Make FileManager a FileChecker. This is empty since FileManager already provides this
// functionality (natively and through our extensions).
extension FileManager: FileChecker {}

// TODO: Evaluate if we should switch to Swift Package Manager's internal `Utility` module that
//       contains `ArgumentParser`. No immediate need, but provides some nice benefits.
/// LaunchArgs reads from UserDefaults to assemble all launch arguments coming from the command line
/// or the Xcode scheme. UserDefaults contains all launch arguments that are in the format of:
/// `-myKey myValue`.
struct LaunchArgs {
  /// Keys associated with the launch args. See `Usage` for descriptions of each flag.
  private enum Key: String, CaseIterable {
    case archs
    case buildDependencies
    case buildRoot
    case carthageBuild
    case carthageSkipVersionCheck
    case customSpecRepos
    case dynamic
    case keepBuildArtifacts
    case localPodspecPath
    case minimumIOSVersion
    case outputDir
    case rc
    case repoDir
    case templateDir
    case updatePodRepo
    case zipPods

    /// Usage description for the key.
    var usage: String {
      switch self {
      case .archs:
        return "The list of architectures to build for. The default list is " +
          "\(Architecture.allCases.map { $0.rawValue })."
      case .buildDependencies:
        return "Whether or not to build dependencies of requested pods. The default is true."
      case .buildRoot:
        return "The root directory for build artifacts. If `nil`, a temporary directory will be " +
          "used."
      case .carthageBuild:
        return "A flag specifying to build Carthage artifacts."
      case .carthageSkipVersionCheck:
        return "A flag to skip the Carthage version check for development iteration."
      case .customSpecRepos:
        return "A comma separated list of custom CocoaPod Spec repos."
      case .dynamic:
        return "A flag specifying to build dynamic library frameworks."
      case .keepBuildArtifacts:
        return "A flag to indicate keeping (not deleting) the build artifacts."
      case .localPodspecPath:
        return "Path to override podspec search with local podspec."
      case .minimumIOSVersion:
        return "The minimum supported iOS version. The default is 10.0."
      case .outputDir:
        return "The directory to copy the built Zip file to."
      case .rc:
        return "The release candidate number, zero indexed."
      case .repoDir:
        return "The path to the repo from which the Firebase distribution is being built."
      case .templateDir:
        return "The path to the directory containing the blank xcodeproj and Info.plist for " +
          "building source based frameworks"
      case .updatePodRepo:
        return "A flag to run `pod repo update` and `pod cache clean -all` before building the " +
          "zip file."
      case .zipPods:
        return "The path to a JSON file of the pods (with optional version) to package into a zip."
      }
    }
  }

  /// The list of architectures to build for.
  let archs: [Architecture]

  /// Build dependencies flag.
  let buildDependencies: Bool

  /// The root directory for build artifacts. If `nil`, a temporary directory will be used.
  let buildRoot: URL?

  /// A flag specifying to build Carthage artifacts.
  let carthageBuild: Bool

  /// Skip the Carthage version check
  let carthageSkipVersionCheck: Bool

  /// Custom CocoaPods spec repos to be used. If not provided, the tool will only use the CocoaPods
  /// master repo.
  let customSpecRepos: [URL]?

  /// A flag that indicates to build dynamic library frameworks. The default is false and static linkage.
  let dynamic: Bool

  /// A flag to keep the build artifacts after this script completes.
  let keepBuildArtifacts: Bool

  /// Path to override podspec search with local podspec.
  let localPodspecPath: URL?

  /// The minimum iOS Version to build for.
  let minimumIOSVersion: String

  /// The directory to copy the built Zip file to. If this is not set, the path to the Zip file will
  /// just be logged to the console.
  let outputDir: URL?

  /// The path to the repo from which the Firebase distribution is being built.
  let repoDir: URL?

  /// The path to the directory containing the blank xcodeproj and Info.plist for building source
  /// based frameworks.
  let templateDir: URL

  /// The release candidate number, zero indexed.
  let rcNumber: Int?

  /// A flag to update the Pod Repo or not.
  let updatePodRepo: Bool

  /// The path to a JSON file listing the pods to repackage to a zip.
  let zipPods: [CocoaPodUtils.VersionedPod]?

  /// The shared instance for processing launch args using default arguments.
  static let shared: LaunchArgs = LaunchArgs()

  /// Initializes with values pulled from the instance of UserDefaults passed in.
  ///
  /// - Parameters:
  ///   - defaults: User defaults containing launch arguments. Defaults to `standard`.
  ///   - fileChecker: An object that can check if a file exists or not. Defaults to
  ///                  `FileManager.default`.
  init(userDefaults defaults: UserDefaults = UserDefaults.standard,
       fileChecker: FileChecker = FileManager.default) {
    // Override default values for specific keys.
    //   - Always run `pod repo update` and pod cache clean -all` unless explicitly set to false.
    defaults.register(defaults: [Key.updatePodRepo.rawValue: true])
    //   - Always build dependencies unless explicitly set to false.
    defaults.register(defaults: [Key.buildDependencies.rawValue: true])

    // Get the project repo directory, and fail if it doesn't exist and we're building Firebase.
    if let repoPath = defaults.string(forKey: Key.repoDir.rawValue) {
      repoDir = URL(fileURLWithPath: repoPath)
    } else if defaults.string(forKey: Key.zipPods.rawValue) == nil {
      LaunchArgs.exitWithUsageAndLog("Missing required key: `\(Key.repoDir)` for the folder " +
        "containing the repository from which we're building the zip.")
    } else {
      repoDir = nil
    }

    // Get the project template directory, and fail if it doesn't exist.
    var templatePath = defaults.string(forKey: Key.templateDir.rawValue)
    if templatePath == nil, let repoDir = repoDir {
      templatePath = repoDir.path + "/ReleaseTooling/Template"
    }
    if templatePath == nil {
      LaunchArgs.exitWithUsageAndLog("Missing required key: `\(Key.templateDir)` for the folder " +
        "containing all required files to build frameworks.")
    }
    templateDir = URL(fileURLWithPath: templatePath!)

    // Parse the archs list.
    if let archs = defaults.string(forKey: Key.archs.rawValue) {
      let archs = archs.components(separatedBy: ",")
      var archList: [Architecture] = []
      for arch in archs {
        guard let addArch = Architecture(rawValue: arch) else {
          LaunchArgs.exitWithUsageAndLog("Specified arch option \(arch) " +
            "must be one of \(Architecture.allCases.map { $0.rawValue })")
        }
        archList.append(addArch)
      }
      self.archs = archList
    } else {
      // No argument was passed in.
      archs = Architecture.allCases
    }

    // Parse the zipPods key.
    if let zipPodsPath = defaults.string(forKey: Key.zipPods.rawValue) {
      let url = URL(fileURLWithPath: zipPodsPath)
      guard fileChecker.fileExists(atPath: url.path) else {
        LaunchArgs.exitWithUsageAndLog("Could not parse \(Key.zipPods) key: value passed " +
          "in is not a file URL or the file does not exist. Value: \(zipPodsPath)")
      }
      do {
        // Get pods, with optional version, from the JSON file.
        let jsonData = try Data(contentsOf: url)
        zipPods = try JSONDecoder().decode([CocoaPodUtils.VersionedPod].self, from: jsonData)
      } catch {
        fatalError("Could not read and parse JSON file at \(url). \(error)")
      }
    } else {
      zipPods = nil
    }

    // Parse the output directory key.
    if let outputPath = defaults.string(forKey: Key.outputDir.rawValue) {
      let url = URL(fileURLWithPath: outputPath)
      guard fileChecker.directoryExists(at: url) else {
        LaunchArgs.exitWithUsageAndLog("Could not parse \(Key.outputDir) key: value " +
          "passed in is not a file URL or the directory does not exist. Value: \(outputPath)")
      }

      outputDir = url.standardizedFileURL
    } else {
      // No argument was passed in.
      outputDir = nil
    }

    // Parse the local podspec search path.
    if let localPath = defaults.string(forKey: Key.localPodspecPath.rawValue) {
      let url = URL(fileURLWithPath: localPath)
      guard fileChecker.directoryExists(at: url) else {
        LaunchArgs.exitWithUsageAndLog("Could not parse \(Key.localPodspecPath) key: value " +
          "passed in is not a file URL or the directory does not exist. Value: \(localPath)")
      }

      localPodspecPath = url.standardizedFileURL
    } else {
      // No argument was passed in.
      localPodspecPath = nil
    }

    // Parse the release candidate number. Note: if the String passed in isn't an integer, ignore
    // it and don't fail since we can append something else to the filenames.
    if let rcFlag = defaults.string(forKey: Key.rc.rawValue),
      !rcFlag.isEmpty,
      let parsedFlag = Int(rcFlag) {
      print("Parsed release candidate version number \(parsedFlag).")
      rcNumber = parsedFlag
    } else {
      print("Did not parse a release candidate version number.")
      rcNumber = nil
    }

    // Parse the custom specs key.
    if let customSpecs = defaults.string(forKey: Key.customSpecRepos.rawValue) {
      // Custom specs are passed in as a comma separated list of URLs. Split the String by each
      // comma and map it to URLs. If any URL is invalid, fail immediately.
      let specs = customSpecs.split(separator: ",").map { (specStr: Substring) -> URL in
        guard let spec = URL(string: String(specStr)) else {
          LaunchArgs.exitWithUsageAndLog("Error parsing specs: \(specStr) is not a valid URL.")
        }

        return spec
      }

      customSpecRepos = specs
    } else {
      // No argument was passed in.
      customSpecRepos = nil
    }

    // Parse the Build Root key.
    if let buildRoot = defaults.string(forKey: Key.buildRoot.rawValue) {
      let url = URL(fileURLWithPath: buildRoot)
      guard fileChecker.directoryExists(at: url) else {
        LaunchArgs.exitWithUsageAndLog("Could not parse \(Key.buildRoot) key: value " +
          "passed in is not a file URL or the directory does not exist. Value: \(buildRoot)")
      }

      self.buildRoot = url.standardizedFileURL
      FileManager.registerBuildRoot(buildRoot: url.standardizedFileURL)
    } else {
      // No argument was passed in.
      buildRoot = nil
    }

    // Parse the minimum iOS version key.
    if let minVersion = defaults.string(forKey: Key.minimumIOSVersion.rawValue) {
      minimumIOSVersion = minVersion
    } else {
      // No argument was passed in.
      minimumIOSVersion = "10.0"
    }

    buildDependencies = defaults.bool(forKey: Key.buildDependencies.rawValue)
    carthageBuild = defaults.bool(forKey: Key.carthageBuild.rawValue)
    carthageSkipVersionCheck = defaults.bool(forKey: Key.carthageSkipVersionCheck.rawValue)
    dynamic = defaults.bool(forKey: Key.dynamic.rawValue)
    updatePodRepo = defaults.bool(forKey: Key.updatePodRepo.rawValue)
    keepBuildArtifacts = defaults.bool(forKey: Key.keepBuildArtifacts.rawValue)

    if !buildDependencies && zipPods == nil {
      LaunchArgs.exitWithUsageAndLog("The -buildDependencies option cannot be false unless a " +
        "list of pods is specified with the -zipPods option.")
    }

    // Check for extra invalid options.
    let validArgs = Key.allCases.map { $0.rawValue }
    for arg in ProcessInfo.processInfo.arguments {
      let dashDroppedArg = String(arg.dropFirst())
      if arg.starts(with: "-"), !validArgs.contains(dashDroppedArg) {
        LaunchArgs.exitWithUsageAndLog("\(arg) is not a valid option.")
      }
    }
  }

  /// Prints an error that occurred, the proper usage String, and quits the application.
  private static func exitWithUsageAndLog(_ errorText: String) -> Never {
    print(errorText)

    // Loop over all the possible keys and print their description.
    print("Usage: `swift run zip-builder [ARGS]` where args are:")
    for option in Key.allCases {
      print("""
      -\(option.rawValue) <VALUE>
          \(option.usage)
      """)
    }

    fatalError("Invalid arguments. See output above for specific error and usage instructions.")
  }
}
