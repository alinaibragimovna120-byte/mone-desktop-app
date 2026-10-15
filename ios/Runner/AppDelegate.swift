import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "SharedFilesPlugin") {
      SharedFilesPlugin.register(with: registrar)
    }
  }
}

/// Принимает файлы, которыми поделились из других приложений
/// (Telegram, Почта, «Файлы»…), и отдаёт их программе через канал
/// mone/shared_files.
class SharedFilesPlugin: NSObject, FlutterPlugin, FlutterSceneLifeCycleDelegate {
  private var channel: FlutterMethodChannel?

  /// Скопированные файлы, которые программа ещё не забрала.
  private var pending: [String] = []

  private static var sharedDir: URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("shared", isDirectory: true)
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    try? FileManager.default.removeItem(at: sharedDir)
    let instance = SharedFilesPlugin()
    let channel = FlutterMethodChannel(
      name: "mone/shared_files", binaryMessenger: registrar.messenger())
    instance.channel = channel
    registrar.addMethodCallDelegate(instance, channel: channel)
    registrar.addSceneDelegate(instance)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "takeFiles" {
      result(pending)
      pending.removeAll()
    } else {
      result(FlutterMethodNotImplemented)
    }
  }

  // Программа была закрыта и запущена ради файла.
  @objc(scene:willConnectToSession:options:)
  func scene(
    _ scene: UIScene, willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions?
  ) -> Bool {
    guard let contexts = connectionOptions?.urlContexts, !contexts.isEmpty else { return false }
    return receive(contexts.map { $0.url })
  }

  // Программа уже была открыта.
  @objc(scene:openURLContexts:)
  func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) -> Bool {
    return receive(URLContexts.map { $0.url })
  }

  /// Каждый файл — в своей папке, чтобы сохранить исходное имя.
  private func receive(_ urls: [URL]) -> Bool {
    let fm = FileManager.default
    var added = false
    for url in urls where url.isFileURL {
      let access = url.startAccessingSecurityScopedResource()
      defer { if access { url.stopAccessingSecurityScopedResource() } }
      let dir = Self.sharedDir.appendingPathComponent(UUID().uuidString, isDirectory: true)
      let target = dir.appendingPathComponent(url.lastPathComponent)
      do {
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try fm.copyItem(at: url, to: target)
        pending.append(target.path)
        added = true
        // iOS кладёт присланный файл в Documents/Inbox — копия больше не нужна.
        if url.path.contains("/Inbox/") { try? fm.removeItem(at: url) }
      } catch {}
    }
    if added { channel?.invokeMethod("filesAvailable", arguments: nil) }
    return added
  }
}
