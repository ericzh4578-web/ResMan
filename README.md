# 实现ArkTS与Native交互功能

### 简介

本Codelab主要介绍如何实现ArkTS与Native C++层交互开发。主要包含以下两个主题：Native侧回调ArkTS函数和Native子线程与UI主线程通信。Native侧回调ArkTS函数分别使用同步任务Callback、异步任务Callback以及异步任务Promise三种方式实现；Native子线程与UI主线程通信分别使用线程安全函数和LibUV异步库两种方式实现。

### 效果预览

![](screenshots/device/native_case.gif)

### 使用说明

在主页面中点击对应按钮会分别跳转到不同场景的页面。在每个场景页面中都包含了一个信息展示区域和一个按钮，点击按钮会调用接口将相关信息显示到信息展示区域上。

### 工程结构

```
├──entry/src/main/cpp                   // C++代码区
│  ├──AsyncCallback                     // 异步Callback方式回调
│  │  ├──AsyncCallback.cpp                
│  │  └──AsyncCallback.h  
│  ├──AsyncPromise                      // 异步Promise方式回调
│  │  ├──AsyncPromise.cpp                
│  │  └──AsyncPromise.h  
│  ├──LibUvCase                         // LibUV异步库方式通信
│  │  ├──LibUvCase.cpp                
│  │  └──LibUvCase.h  
│  ├──SyncCallback                      // 同步Callback方式回调
│  │  ├──SyncCallback.cpp                
│  │  └──SyncCallback.h  
│  ├──ThreadSafeCase                    // 线程安全函数方式通信
│  │  ├──ThreadSafeCase.cpp                
│  │  └──ThreadSafeCase.h  
│  ├──types
│  │  └──libentry                       // C++接口导出
│  │     ├──Index.d.ts                
│  │     └──oh-package.json5           
│  ├──CMakeLists.txt                    // Cmake配置文件 
│  └──napi_init.cpp                     // Native侧接口映射
├──entry/src/main/ets                   // ArkTS代码区                  
│  ├──entryability        
│  │  └──EntryAbility.ets                                
│  ├──entrybackupability 
│  │  └──EntryBackupAbility.ets                           
│  ├──pages     
│  │  ├──Index.ets                      // 主页面 
│  │  ├──SubMainThreadCom.ets           // Native侧回调ArkTS函数页面 
│  │  └──SyncAndAsyncWork.ets           // Native子线程与UI主线程通信页面           
│  └──view    
│     └──TitleComponent.ets             // 标题组件        
└──entry/src/main/resources             // 应用资源文件
```

### 相关权限

**不涉及**

### 参考资料

**不涉及**

### 约束与限制

1. 本示例仅支持标准系统上运行，支持设备：华为手机。
2. HarmonyOS系统：HarmonyOS 5.0.5 Release及以上。
3. DevEco Studio版本：DevEco Studio 6.0.2 Release及以上。
4. HarmonyOS SDK版本：HarmonyOS 6.0.2 Release SDK及以上。