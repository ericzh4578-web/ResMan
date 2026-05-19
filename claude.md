# NativeCase 项目开发指南


## TODO
1. ✅ 资源模拟模块 — 已完成 (ResourceSimulator C++ 模块 + ResourceSimulatorPage UI)
   - CPU负载模拟：0%、25%、50%、75%、100%（通过后台线程占空比实现）
   - 内存负载：占用 25%、50%、80% 物理内存（大块内存分配 + memset 提交物理页）
   - I/O随机读写：弱、中、强 三档（不同 block size + sleep 间隔）
2. ✅ 支持不同模型路径的选择 — 已完成 (独立 ModelSelectorPage 页面 + TestDashboardPage 集成)
3. ✅ YOLO 推理压测 — 已完成 (TestDashboardPage: 自定义推理次数 + 批次推理 + 随机输入压测)

## 项目概述

**NativeCase** 是一个 HarmonyOS 应用示例项目，展示了 ArkTS 与 Native C++ 层的交互开发。项目包含两个主要主题：
1. **Native 侧回调 ArkTS 函数** - 使用同步 Callback、异步 Callback、异步 Promise 三种方式
2. **Native 子线程与 UI 主线程通信** - 使用线程安全函数和 LibUV 异步库两种方式

## 项目结构

```
NativeCase/
├── entry/src/main/cpp/                    # C++ 原生代码
│   ├── SyncCallback/                      # 同步回调实现
│   │   ├── SyncCallback.h
│   │   └── SyncCallback.cpp
│   ├── AsyncCallback/                     # 异步回调实现
│   │   ├── AsyncCallback.h
│   │   └── AsyncCallback.cpp
│   ├── AsyncPromise/                      # 异步 Promise 实现
│   │   ├── AsyncPromise.h
│   │   └── AsyncPromise.cpp
│   ├── ThreadSafeCase/                    # 线程安全函数通信
│   │   ├── ThreadSafeCase.h
│   │   └── ThreadSafeCase.cpp
│   ├── LibUvCase/                         # LibUV 异步库通信
│   │   ├── LibUvCase.h
│   │   └── LibUvCase.cpp
│   ├── types/libentry/                    # TypeScript 类型定义
│   │   ├── Index.d.ts
│   │   └── oh-package.json5
│   ├── napi_init.cpp                      # NAPI 模块初始化和导出
│   └── CMakeLists.txt                     # CMake 构建配置
├── entry/src/main/ets/                    # ArkTS 代码
│   ├── pages/
│   │   ├── Index.ets                      # 主页面
│   │   ├── SubMainThreadCom.ets           # 线程通信页面
│   │   └── SyncAndAsyncWork.ets           # 同步异步工作页面
│   ├── view/
│   │   └── TitleComponent.ets             # 标题组件
│   └── entryability/
│       └── EntryAbility.ets               # 应用入口
├── entry/src/main/resources/              # 应用资源
└── CMakeLists.txt                         # 根级 CMake 配置
```

## Native C++ 开发规范

### 1. 代码组织

- **头文件 (.h)**：放在模块目录下，包含类定义和接口声明
- **实现文件 (.cpp)**：包含具体实现逻辑
- **命名规范**：
  - 类名使用 PascalCase（如 `SyncCallback`）
  - 方法名使用 camelCase（如 `SyncCallbackRead`）
  - 常量使用 UPPER_SNAKE_CASE（如 `g_contextLen`）

### 2. NAPI 接口导出

所有 Native 函数必须通过 `napi_init.cpp` 导出：

```cpp
// napi_init.cpp 中的导出示例
napi_property_descriptor desc[] = {
    {"functionName", nullptr, NativeFunction, nullptr, nullptr, nullptr, napi_default, nullptr},
};
napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
```

对应的 TypeScript 类型定义在 `types/libentry/Index.d.ts` 中：

```typescript
export const functionName: (param: type) => ReturnType;
```

### 3. 内存管理

- **使用 std::unique_ptr**：管理动态分配的内存
  ```cpp
  std::unique_ptr<char[]> buffer = std::make_unique<char[]>(size);
  ```
- **NAPI 引用管理**：
  - 使用 `napi_create_reference` 创建引用
  - 使用 `napi_delete_reference` 释放引用
  - 避免内存泄漏

### 4. 线程安全

#### 同步回调 (SyncCallback)
- 直接在调用线程执行
- 适合快速操作
- 不能进行长时间阻塞操作

#### 异步回调 (AsyncCallback)
- 使用 `napi_create_async_work` 创建异步任务
- 包含 ExecuteCB（后台线程执行）和 CompleteCB（主线程回调）
- 适合 I/O 操作和文件读取

#### 异步 Promise (AsyncPromise)
- 返回 Promise 对象
- 使用 `napi_create_promise` 创建 Promise
- 在后台线程完成后 resolve/reject

#### 线程安全函数 (ThreadSafeCase)
- 使用 `napi_call_threadsafe_function` 从子线程调用 JS 回调
- 需要创建线程安全函数引用
- 适合多线程场景

#### LibUV 异步库 (LibUvCase)
- 使用 libuv 的事件循环
- 通过 `uv_queue_work` 提交异步任务
- 自动处理线程池管理

### 5. 资源管理

使用 HarmonyOS 资源管理器读取应用资源：

```cpp
// 初始化资源管理器
NativeResourceManager *resMgr = OH_ResourceManager_InitNativeResourceManager(env, args[1]);

// 打开文件
RawFile *file = OH_ResourceManager_OpenRawFile(resMgr, fileName);

// 读取文件
OH_ResourceManager_ReadRawFile(file, buffer, size);

// 关闭和释放
OH_ResourceManager_CloseRawFile(file);
OH_ResourceManager_ReleaseNativeResourceManager(resMgr);
```

### 6. 错误处理

- 检查 NAPI 函数返回值
- 使用 `napi_throw_error` 抛出异常
- 验证参数数量和类型

```cpp
if (argc < 3) {
    napi_throw_error(env, nullptr, "Expected 3 arguments");
    return nullptr;
}
```

### 7. 编译配置 (CMakeLists.txt)

```cmake
cmake_minimum_required(VERSION 3.5.0)
project(NativeCase)

# 包含目录
include_directories(${CMAKE_CURRENT_SOURCE_DIR})

# 创建共享库
add_library(entry SHARED 
    napi_init.cpp 
    SyncCallback/SyncCallback.cpp 
    AsyncCallback/AsyncCallback.cpp
    # ... 其他源文件
)

# 链接库
target_link_libraries(entry PUBLIC 
    libace_napi.z.so      # NAPI 库
    librawfile.z.so       # 资源管理库
    libuv.so              # LibUV 库
)
```

## ArkTS 开发规范

### 1. 导入 Native 模块

```typescript
import libentry from 'libentry.so';
```

### 2. 调用 Native 函数

```typescript
// 同步回调
libentry.syncCallbackRead(fileName, resourceManager, (result) => {
    console.log(result);
});

// 异步 Promise
libentry.asyncPromiseRead(fileName, resourceManager)
    .then(result => console.log(result))
    .catch(error => console.error(error));
```

### 3. 资源管理器获取

```typescript
import { getContext } from '@kit.AbilityKit';
import { resourceManager } from '@kit.LocalizationKit';

const context = getContext(this);
const resMgr = context.resourceManager;
```

## 开发步骤

### 1. 添加新的 Native 功能

1. 在 `entry/src/main/cpp/` 下创建新模块目录
2. 编写 `.h` 和 `.cpp` 文件
3. 在 `CMakeLists.txt` 中添加源文件
4. 在 `napi_init.cpp` 中导出函数
5. 在 `types/libentry/Index.d.ts` 中添加类型定义

### 2. 编译和构建

```bash
# 使用 DevEco Studio 构建
# 或命令行构建
hvigorw build
```

### 3. 测试

- 在 ArkTS 页面中调用 Native 函数
- 使用 HiLog 进行调试输出
- 验证回调和 Promise 返回值

## 关键库和 API

| 库/API | 用途 |
|--------|------|
| `libace_napi.z.so` | NAPI 接口，用于 JS-Native 交互 |
| `librawfile.z.so` | 资源管理，读取应用资源文件 |
| `libuv.so` | 异步 I/O 库，事件驱动编程 |
| `napi/native_api.h` | NAPI 核心头文件 |
| `rawfile/raw_file_manager.h` | 资源管理 API |

## TestDashboardPage 函数参考

`entry/src/main/ets/pages/TestDashboardPage.ets` — 统一测试面板，整合资源监控、资源模拟、模型选择和YOLO推理压测。

### 常量

| 常量 | 值 | 说明 |
|------|-----|------|
| `POLL_INTERVAL_MS` | `1000` | 监控/模拟状态轮询间隔 (ms) |
| `INFI_MODELS` | `['infi_coco_full_bsz1.ms']` | 可选 InFi 模型文件列表 |
| `YOLO_MODELS` | `['yolov8n_bsz4.ms', 'yolov8s_bsz4.ms', 'yolov8m_bsz4.ms', 'yolov8l_bsz4.ms', 'yolov8x_bsz4.ms']` | 可选 YOLO 模型文件列表 |
| `CPU_LEVELS` | `['0%', '25%', '50%', '75%', '100%']` | CPU 负载档位标签 |
| `MEM_LEVELS` | `['10%', '15%', '20%', '25%']` | 内存负载档位标签 |
| `IO_LEVELS` | `['Weak', 'Medium', 'Strong']` | I/O 负载档位标签 |

### @State 响应式变量

**Monitor 组:**
| 变量 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `cpuUsage` | `number` | `0` | 本进程 CPU 占用百分比 |
| `systemCpuUsage` | `number` | `0` | 系统 CPU 占用百分比 |
| `pssMb` | `string` | `'-'` | 进程 PSS 内存 (MB) |
| `sysMemInfo` | `string` | `'-'` | 系统内存概况 (Total/Free/Avail) |
| `thermalLevel` | `number` | `0` | 设备热等级 |
| `batterySOC` | `number` | `0` | 电池电量百分比 |
| `batteryTemp` | `number` | `0` | 电池温度 (°C) |

**Simulator 组:**
| 变量 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `cpuLevel` | `number` | `0` | 当前 CPU 档位 (0-4) |
| `cpuActive` | `boolean` | `false` | CPU 负载是否运行中 |
| `memLevel` | `number` | `0` | 当前内存档位 (0-3) |
| `memActive` | `boolean` | `false` | 内存负载是否激活 |
| `ioLevel` | `number` | `0` | 当前 I/O 档位 (0-2) |
| `ioActive` | `boolean` | `false` | I/O 负载是否运行中 |

**Model 组:**
| 变量 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `selectedInfi` | `string` | `INFI_MODELS[0]` | 当前选中的 InFi 模型文件名 |
| `selectedYolo` | `string` | `YOLO_MODELS[3]` | 当前选中的 YOLO 模型文件名 (默认 yolov8l) |
| `modelStatus` | `string` | `'Idle'` | 模型加载状态 (`Idle`/`Loading…`/`OK`/`Failed`) |
| `modelResult` | `string` | `''`` | 模型加载结果文本 |

**Inference 组:**
| 变量 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `inferCount` | `number` | `10` | 推理迭代次数 |
| `inferBatchSize` | `number` | `4` | 批次大小 (从模型文件名提取) |
| `inferRunning` | `boolean` | `false` | 推理压测是否进行中 |
| `inferStatus` | `string` | `'Idle'` | 推理状态 |
| `inferResult` | `string` | `''` | 推理压测结果 |

### 生命周期

| 函数 | 触发时机 | 行为 |
|------|---------|------|
| `aboutToAppear()` | 页面挂载 | 启动 1s 定时器轮询 `refreshMonitor()` + `refreshSimulator()` |
| `aboutToDisappear()` | 页面卸载 | 清除定时器，调用 `stopAll()` 停止所有负载 |

### Monitor 组函数

| 函数 | 参数 | 返回值 | 说明 |
|------|------|--------|------|
| `refreshMonitor()` | 无 | `void` | 读取 CPU/PSS/系统内存/热等级/电池 并更新 @State |

### Simulator 组函数

| 函数 | 参数 | 返回值 | 说明 |
|------|------|--------|------|
| `refreshSimulator()` | 无 | `void` | 调用 `libentry.getSimulatorStatus()` 同步激活状态 |
| `applyCpu(lvl)` | `lvl: number` (0-4) | `void` | 调用 `libentry.startCpuLoad(lvl)` 启动/调整 CPU 负载 |
| `applyMem(lvl)` | `lvl: number` (0-3) | `void` | 调用 `libentry.startMemoryLoad(lvl)` 分配内存 |
| `stopMem()` | 无 | `void` | 调用 `libentry.stopMemoryLoad()` 释放内存 |
| `applyIo(lvl)` | `lvl: number` (0-2) | `void` | 调用 `libentry.startIoLoad(lvl, filesDir)` 启动 I/O 负载 |
| `stopIo()` | 无 | `void` | 调用 `libentry.stopIoLoad()` 停止 I/O 并删除临时文件 |
| `stopAll()` | 无 | `void` | 一次调用停止所有 CPU/内存/IO 负载 |

### Model 组函数

| 函数 | 参数 | 返回值 | 说明 |
|------|------|--------|------|
| `testModels()` | 无 | `Promise<void>` | 从 rawfile 加载 InFi (CPU) 和 YOLO (NNRT) 模型，测量加载耗时 |

### Inference Benchmark 函数

| 函数 | 参数 | 返回值 | 说明 |
|------|------|--------|------|
| `getBatchSize(modelName)` | `modelName: string` | `number` | 从文件名提取 `_bszN` 中的 N，无匹配返回 1 |
| `generateRandomInput(batchSize)` | `batchSize: number` | `ArrayBuffer` | 生成 640×640×3×batchSize 的随机 Float32Array 作为推理输入 |
| `runYoloBenchmark()` | 无 | `Promise<void>` | 加载 YOLO 模型 → 热身 1 次 → 循环 `inferCount` 次推理 → 输出 总时间/平均延迟/FPS/吞吐量 |

### UI Builder

| Builder | 参数 | 说明 |
|---------|------|------|
| `sectionTitle(t)` | `t: string` | 渲染区域标题 (15px 粗体) |
| `metricRow(label, value)` | `label: string, value: string` | 渲染键值行 (当前未使用) |

### 页面布局 (3段式)

```
┌─────────────────────────────┐
│  Resource Monitor           │  ← 实时系统指标 (CPU/PSS/内存/热/电池)
├─────────────────────────────┤
│  Resource Simulator         │  ← CPU/Memory/IO 负载档位按钮 + Stop All
├─────────────────────────────┤
│  Model Selector             │  ← InFi/YOLO 下拉选择 + Test Load
│  ├ Divider ─────────────────│
│  └ YOLO Inference Benchmark │  ← Count 输入 + Batch Size + Run 按钮 + 结果
└─────────────────────────────┘
```

## 常见问题

### Q: 何时使用同步 vs 异步回调？
**A:** 
- 同步：快速操作（< 10ms）
- 异步：I/O 操作、文件读取、网络请求

### Q: 如何避免内存泄漏？
**A:**
- 使用智能指针（`std::unique_ptr`）
- 及时释放 NAPI 引用
- 在 `Destroy` 函数中清理全局资源

### Q: 线程安全函数和 LibUV 的区别？
**A:**
- 线程安全函数：更灵活，适合复杂场景
- LibUV：更简洁，自动管理线程池

## 环境要求

- HarmonyOS 5.0.5 Release 及以上
- DevEco Studio 6.0.2 Release 及以上
- HarmonyOS SDK 6.0.2 Release 及以上
- CMake 3.5.0 及以上

## 参考资源

- HarmonyOS NAPI 官方文档
- HarmonyOS 资源管理 API
- LibUV 官方文档
- 项目中的示例代码（SyncCallback、AsyncCallback 等）

## 许可证

Apache License 2.0
