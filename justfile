# 列出常用任务
[default]
list:
    @just --list

# 编译 macOS 程序
build:
    make build

# 运行 macOS 测试
test:
    make test

# 构建 macOS 应用包；可传 release
app config="debug":
    make app CONFIG={{ quote(config) }}

# 构建并在 AeroSpace workspace 8 打开 macOS 应用；可传 release
run config="debug": (app config)
    aerospace workspace 8
    open .build/app/Kumone.app

# 将 release 应用打包为 ZIP（本地构建签名）
package: (app "release")
    ditto -c -k --sequesterRsrc --keepParent .build/app/Kumone.app .build/app/Kumone.zip

# 清理构建产物
clean:
    make clean
