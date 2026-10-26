import AppKit

// MARK: - 不需要启动界面的入口

let arguments = CommandLine.arguments

if arguments.contains("--help") || arguments.contains("-h") {
    print("""
    桌宠合集 PetHub 1.0.0
    薄肌 · 太对了 · 峰哥 · 果冻，四只桌宠住在一个 App 里。

    用法：PetHub [选项]

      无参数                 启动合集，四只桌宠一起出现
      --self-test            跑全量自检，最后一行必须是 PASS
      --chain-test           模拟点一下薄肌，跑完整四步捧哏链并校验
      --dump-state           打印四只桌宠的状态后退出
      --preview <目录>       把四只桌宠的画面渲染成 PNG 后退出
      --trace                把联动的每一跳打到 stdout
      --probe-sensor         检查这台 Mac 有没有运动传感器
      -h, --help             显示这段帮助
    """)
    exit(0)
}

// 太对了的「机身摇晃」需要直接读 SPU 传感器。为了不把 IOKit 的权限问题带进主进程，
// 原来 SunPet 的做法是把自己再拉起来一个 helper 进程；合集沿用同一套，参数保持不变。
if arguments.count == 5,
   arguments[1] == "--motion-helper",
   let port = UInt16(arguments[2]), port > 1024,
   let parent = Int32(arguments[4]), parent > 1 {
    SensorHelper().run(port: port, token: arguments[3], parent: parent)
}

if arguments.contains("--probe-sensor") {
    if let service = accelerometerService(), let device = IOHIDDeviceCreate(kCFAllocatorDefault, service) {
        let result = IOHIDDeviceOpen(device, 0)
        print("sensor available; open result=\(result); uid=\(getuid())")
        if result == kIOReturnSuccess { IOHIDDeviceClose(device, 0) }
        IOObjectRelease(service)
    } else {
        print("sensor unavailable")
    }
    exit(0)
}

// MARK: - 正常启动

let app = NSApplication.shared
let delegate = PetHubApp()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()