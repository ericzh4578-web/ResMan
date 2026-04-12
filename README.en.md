# Implementing Interactions Between ArkTS and Native

### Overview

This sample demonstrates how to develop interactions between ArkTS and the native C++ layer. It covers two scenarios: invoking ArkTS functions from the native side and communication between the native child thread and the UI main thread. The invocation of ArkTS function from the native side is implemented through synchronous or asynchronous tasks. The communication between the native child thread and the UI main thread is implemented using thread-safe functions or the libuv asynchronous library.

### Preview

![](screenshots/device/native_case_en.gif)

### How to Use

On the home page, touch the respective button to access scenario-specific pages. Each of these pages contains an information display section and a button. When you touch the button, an interface is invoked to display related information in the information display section.

### Project Structure

```
├──entry/src/main/cpp                   // C++ code area
│  ├──AsyncCallback                     // Asynchronous callback
│  │  ├──AsyncCallback.cpp                
│  │  └──AsyncCallback.h  
│  ├──AsyncPromise                      // Asynchronous promise
│  │  ├──AsyncPromise.cpp                
│  │  └──AsyncPromise.h  
│  ├──LibUvCase                         // Communication via libuv
│  │  ├──LibUvCase.cpp                
│  │  └──LibUvCase.h  
│  ├──SyncCallback                      // Synchronous callback
│  │  ├──SyncCallback.cpp                
│  │  └──SyncCallback.h  
│  ├──ThreadSafeCase                    // Communication using thread-safe functions
│  │  ├──ThreadSafeCase.cpp                
│  │  └──ThreadSafeCase.h  
│  ├──types
│  │  └──libentry                       // Exported C++ APIs
│  │     ├──Index.d.ts                
│  │     └──oh-package.json5           
│  ├──CMakeLists.txt                    // CMake file 
│  └──napi_init.cpp                     // Native API mappings
├──entry/src/main/ets                   // ArkTS code area                  
│  ├──entryability        
│  │  └──EntryAbility.ets                                
│  ├──entrybackupability 
│  │  └──EntryBackupAbility.ets                           
│  ├──pages     
│  │  ├──Index.ets                      // Home page 
│  │  ├──SubMainThreadCom.ets           // Invocation of ArkTS functions on the native side 
│  │  └──SyncAndAsyncWork.ets           // Communication between the native child thread and the UI main thread           
│  └──view    
│     └──TitleComponent.ets             // Title component        
└──entry/src/main/resources             // Resource files
```

### Permissions

**N/A**

### References

**N/A**

### Constraints

1. The sample is only supported on Huawei phones with standard systems.
2. The HarmonyOS version must be HarmonyOS 5.0.5 Release or later.
3. The DevEco Studio version must be DevEco Studio 6.0.2 Release or later.
4. The HarmonyOS SDK version must be HarmonyOS 6.0.2 Release SDK or later.

