# Specimen Manager API 接口文档

> 基于代码自动生成，最后更新: 2026-06-10

## 目录

- [1. 标本管理 (Specimens)](#1-标本管理-specimens)
- [2. 放大倍数管理 (Specimen Ratios)](#2-放大倍数管理-specimen-ratios)
- [3. 标本瓦片管理 (Specimen Tiles)](#3-标本瓦片管理-specimen-tiles)
- [4. 堆叠瓦片管理 (Specimen Tile Stacked)](#4-堆叠瓦片管理-specimen-tile-stacked)
- [5. 瓦片产品管理 (Specimen Tile Products)](#5-瓦片产品管理-specimen-tile-products)
- [6. 产品中心坐标 (Specimen Product Centers)](#6-产品中心坐标-specimen-product-centers)
- [7. 产品标记 (Specimen Product Markers)](#7-产品标记-specimen-product-markers)
- [8. 导航与数据生成 (Navigation)](#8-导航与数据生成-navigation)
- [9. 统计 (Statistics)](#9-统计-statistics)
- [10. 热点问题 (Hotspots)](#10-热点问题-hotspots)
- [11. 第三方接口 (API / Specimens Third)](#11-第三方接口-api--specimens-third)

---

## 1. 标本管理 (Specimens)

**前缀**: `/manager/specimens`  
**标签**: `specimens`

### 1.1 创建标本

- **POST** `/manager/specimens/add`
- **请求体**: `SpecimenCreate`
- **响应**: `Specimen`
- **说明**: 创建新标本，third_id 不可重复

### 1.2 根据 ID 获取标本

- **GET** `/manager/specimens/find/{specimen_id}`
- **路径参数**: `specimen_id` (int)
- **响应**: `SpecimenWithRatios` (含关联的放大倍数列表)

### 1.3 获取标本列表

- **GET** `/manager/specimens/list`
- **查询参数**:
  | 参数 | 类型 | 默认值 | 说明 |
  |------|------|--------|------|
  | skip | int | 0 | 偏移量 |
  | limit | int | 100 | 每页数量 |
- **响应**: `List[Specimen]`

### 1.4 获取标本列表（含放大倍数）

- **GET** `/manager/specimens/list-with-magnifications`
- **查询参数**:
  | 参数 | 类型 | 默认值 | 说明 |
  |------|------|--------|------|
  | skip | int | 0 | 偏移量 |
  | limit | int | 100 | 每页数量 |
  | name | str | None | 按名称过滤 |
  | third_id | str | None | 按第三方 ID 过滤 |
  | status | int | None | 1=启用, 0=禁用 |
- **响应**: `{ specimens: [...], total: int }`

### 1.5 更新标本

- **PUT** `/manager/specimens/{specimen_id}`
- **路径参数**: `specimen_id` (int)
- **请求体**: `SpecimenUpdate`
- **响应**: `Specimen`

### 1.6 删除标本（逻辑删除）

- **DELETE** `/manager/specimens/del/{specimen_id}`
- **路径参数**: `specimen_id` (int)
- **响应**: `{ message: str }`

### 1.7 获取所有采集员

- **GET** `/manager/specimens/collectors`
- **响应**: `List[SpecimenCollector]`

---

## 2. 放大倍数管理 (Specimen Ratios)

**前缀**: `/manager/specimen-ratios`  
**标签**: `specimen_ratios`

### 2.1 创建放大倍数

- **POST** `/manager/specimen-ratios/add`
- **请求体**: `SpecimenRatioCreate`
- **响应**: `SpecimenRatio`

### 2.2 根据 ID 获取放大倍数

- **GET** `/manager/specimen-ratios/find/{ratio_id}`
- **路径参数**: `ratio_id` (int)
- **响应**: `SpecimenRatioWithTiles` (含关联瓦片列表)

### 2.3 获取放大倍数列表

- **GET** `/manager/specimen-ratios/list`
- **查询参数**:
  | 参数 | 类型 | 默认值 | 说明 |
  |------|------|--------|------|
  | skip | int | 0 | 偏移量 |
  | limit | int | 100 | 每页数量 |
- **响应**: `List[SpecimenRatio]`

### 2.4 更新放大倍数

- **PUT** `/manager/specimen-ratios/{ratio_id}`
- **路径参数**: `ratio_id` (int)
- **请求体**: `SpecimenRatioUpdate`
- **响应**: `SpecimenRatio`

### 2.5 删除放大倍数（逻辑删除）

- **DELETE** `/manager/specimen-ratios/del/{ratio_id}`
- **路径参数**: `ratio_id` (int)
- **响应**: `{ message: str }`

---

## 3. 标本瓦片管理 (Specimen Tiles)

**前缀**: `/manager/specimen-tiles`  
**标签**: `specimen_tiles`

### 3.1 创建标本瓦片（中层）并上传图片

- **POST** `/manager/specimen-tiles/mid`
- **Content-Type**: `multipart/form-data`
- **表单参数**:
  | 参数 | 类型 | 必填 | 说明 |
  |------|------|------|------|
  | specimen_id | int | 是 | 标本 ID |
  | ratio_id | int | 是 | 放大倍数 ID |
  | seq_id | int | 是 | 序列 ID |
  | parent_seq | int | 是 | 父级序列 |
  | direction | str | 是 | 方向 |
  | stack_id | int | 是 | 堆叠 ID |
  | collection_date | datetime | 否 | 采集日期 |
  | collector | str | 否 | 采集员 |
  | canvasImage | file | 否 | Canvas 原始图片 |
  | cameraImage | file | 否 | Camera 原始图片 |
- **响应**: `SpecimenTile`
- **说明**: 如果同 specimen_id + ratio_id + seq_id + stack_id 已存在，则更新

### 3.2 根据 ID 获取瓦片

- **GET** `/manager/specimen-tiles/find/{tile_id}`
- **路径参数**: `tile_id` (int)
- **响应**: `SpecimenTile`

### 3.3 获取瓦片列表

- **GET** `/manager/specimen-tiles/list`
- **查询参数**:
  | 参数 | 类型 | 必填 | 默认值 | 说明 |
  |------|------|------|--------|------|
  | specimen_id | int | 是 | - | 标本 ID |
  | ratio_id | int | 是 | - | 放大倍数 ID |
  | stack_id | int | 否 | None | 堆叠 ID |
  | skip | int | 否 | 0 | 偏移量 |
  | limit | int | 否 | 1000 | 每页数量 |
- **响应**: `{ tiles: [...], total: int, skip: int, limit: int }`

### 3.4 更新瓦片

- **PUT** `/manager/specimen-tiles/{tile_id}`
- **路径参数**: `tile_id` (int)
- **请求体**: `SpecimenTileUpdate`
- **响应**: `SpecimenTile`

### 3.5 删除瓦片

- **DELETE** `/manager/specimen-tiles/del/{tile_id}`
- **路径参数**: `tile_id` (int)
- **说明**: 同时删除 OSS 上关联的图片文件
- **响应**: `{ message: str }`

### 3.6 根据第三方 ID 和倍数获取瓦片

- **GET** `/manager/specimen-tiles/by-third-id/{third_id}/{ratio}`
- **路径参数**: `third_id` (int), `ratio` (str)
- **响应**: `List[SpecimenTile]`

### 3.7 根据标本 ID 获取放大倍数

- **GET** `/manager/specimen-tiles/ratio`
- **查询参数**: `specimen_id` (int)
- **响应**: `List[SpecimenRatio]`

### 3.8 获取瓦片图片（代理 OSS）

- **GET** `/manager/specimen-tiles/image`
- **查询参数**: `image_url` (str) — 完整 OSS URL
- **说明**: 代理访问 OSS 图片，解决跨域问题。自动缩放到宽度 1024
- **响应**: 图片二进制流

### 3.9 导出瓦片图片为 ZIP

- **GET** `/manager/specimen-tiles/export`
- **查询参数**:
  | 参数 | 类型 | 必填 | 默认值 | 说明 |
  |------|------|------|--------|------|
  | specimen_id | int | 是 | - | 标本 ID |
  | ratio_id | int | 是 | - | 放大倍数 ID |
  | stack_id | int | 是 | - | 堆叠 ID |
  | layer | str | 否 | "mid" | 图层类型 (仅支持 "mid") |
- **响应**: ZIP 文件 (application/zip)

---

## 4. 堆叠瓦片管理 (Specimen Tile Stacked)

**前缀**: `/manager/specimen-tile-stacked`  
**标签**: `specimen-tile-stacked`

### 4.1 合并多个堆叠

- **POST** `/manager/specimen-tile-stacked/merge-stack`
- **请求体**: `SpecimenTileStackedRequest`
  ```json
  {
    "specimen_id": 1,
    "ratio_id": 1,
    "stack_ids": [1, 2, 3]
  }
  ```
- **说明**: 将多个 stack 的 loc_mid 图像按坐标合成为一张大图，上传到 OSS 并创建新的 stack 记录
- **响应**:
  ```json
  {
    "message": "Successfully merged stacks and created new stack",
    "new_stack_id": 10,
    "specimen_id": 1,
    "ratio_id": 1,
    "original_stack_count": 3,
    "oss_url": "https://..."
  }
  ```

### 4.2 根据 ID 获取堆叠

- **GET** `/manager/specimen-tile-stacked/find/{stacked_id}`
- **路径参数**: `stacked_id` (int)
- **响应**: `SpecimenTileStacked`

### 4.3 获取堆叠列表

- **GET** `/manager/specimen-tile-stacked/list`
- **查询参数**:
  | 参数 | 类型 | 必填 | 说明 |
  |------|------|------|------|
  | specimen_id | int | 是 | 标本 ID |
  | ratio_id | int | 是 | 放大倍数 ID |
  | skip | int | 否 | 偏移量 (默认 0) |
  | limit | int | 否 | 每页数量 (默认 100) |
- **响应**: `List[SpecimenTileStacked]`

### 4.4 创建堆叠记录

- **POST** `/manager/specimen-tile-stacked/create`
- **请求体**: `SpecimenTileStackedCreate`
- **响应**: `SpecimenTileStacked`

### 4.5 更新堆叠记录

- **PUT** `/manager/specimen-tile-stacked/update/{stacked_id}`
- **路径参数**: `stacked_id` (int)
- **请求体**: `SpecimenTileStackedUpdate`
- **响应**: `SpecimenTileStacked`

### 4.6 删除堆叠记录（物理删除）

- **DELETE** `/manager/specimen-tile-stacked/del/{stacked_id}`
- **路径参数**: `stacked_id` (int)
- **说明**: 物理删除，同时清理关联的 OSS 图片（stack 自身 + SpecimenTileProduct + SpecimenTile 的图片）
- **响应**: `{ message: str }`

### 4.7 拆分堆叠到地图

- **POST** `/manager/specimen-tile-stacked/split-to-map`
- **Content-Type**: `multipart/form-data`
- **表单参数**:
  | 参数 | 类型 | 必填 | 说明 |
  |------|------|------|------|
  | stack_id | int | 是 | 堆叠 ID |
- **说明**: 对 loc_mid 图像执行去背景、低通滤波、切分为 512x512 瓦片，上传到 OSS 并存入 specimen_tile_product 表
- **响应**:
  ```json
  {
    "message": "Successfully processed split for stack_id: 1",
    "specimen_id": 1,
    "ratio_id": 1,
    "stack_id": 1,
    "loc_mid_tiles": 16,
    "loc_top_tiles": 16,
    "loc_bottom_tiles": 16
  }
  ```

### 4.8 上传成品图

- **POST** `/manager/specimen-tile-stacked/upload-finished-image`
- **Content-Type**: `multipart/form-data`
- **表单参数**:
  | 参数 | 类型 | 必填 | 说明 |
  |------|------|------|------|
  | stack_id | int | 是 | 堆叠 ID |
  | specimen_id | int | 是 | 标本 ID |
  | ratio_id | int | 是 | 放大倍数 ID |
  | layer | str | 是 | 图层类型 ("mid" 或 "top") |
  | image | file | 否 | 图片文件 |
- **说明**: 上传成品图到 OSS 并更新堆叠记录，自动删除旧 OSS 文件
- **响应**: `SpecimenTileStacked`

### 4.9 批量拆分所有活跃堆叠

- **POST** `/manager/specimen-tile-stacked/split-to-map-all`
- **说明**: 在后台异步处理所有活跃 (status=1) 的堆叠记录
- **响应**:
  ```json
  {
    "message": "Submitted processing for 5 active stacked records in the background",
    "total_submitted": 5
  }
  ```

### 4.10 导出成品图

- **GET** `/manager/specimen-tile-stacked/export-finished-image`
- **查询参数**:
  | 参数 | 类型 | 必填 | 说明 |
  |------|------|------|------|
  | stack_id | int | 是 | 堆叠 ID |
- **说明**: 根据坐标将所有瓦片合成一张大图返回 PNG
- **响应**: PNG 图片 (image/png)

---

## 5. 瓦片产品管理 (Specimen Tile Products)

**前缀**: `/manager/specimen-tile-products`  
**标签**: `specimen-tile-products`

### 5.1 创建瓦片产品

- **POST** `/manager/specimen-tile-products/add`
- **请求体**: `SpecimenTileProductCreate`
- **响应**: `SpecimenTileProduct`

### 5.2 根据 ID 获取瓦片产品

- **GET** `/manager/specimen-tile-products/find/{tile_product_id}`
- **路径参数**: `tile_product_id` (int)
- **响应**: `SpecimenTileProduct`

### 5.3 获取瓦片产品列表

- **GET** `/manager/specimen-tile-products/list`
- **查询参数**:
  | 参数 | 类型 | 必填 | 默认值 | 说明 |
  |------|------|------|--------|------|
  | specimen_id | int | 是 | - | 标本 ID |
  | ratio_id | int | 是 | - | 放大倍数 ID |
  | stack_id | int | 否 | None | 堆叠 ID |
  | skip | int | 否 | 0 | 偏移量 |
  | limit | int | 否 | 1000 | 每页数量 |
- **响应**: `List[SpecimenTileProduct]`

### 5.4 更新瓦片产品

- **PUT** `/manager/specimen-tile-products/{tile_product_id}`
- **路径参数**: `tile_product_id` (int)
- **请求体**: `SpecimenTileProductUpdate`
- **响应**: `SpecimenTileProduct`

### 5.5 删除瓦片产品

- **DELETE** `/manager/specimen-tile-products/del/{tile_product_id}`
- **路径参数**: `tile_product_id` (int)
- **响应**: `{ message: str }`

---

## 6. 产品中心坐标 (Specimen Product Centers)

**前缀**: `/manager/specimen-product-centers`  
**标签**: `specimen_product_centers`

### 6.1 创建产品中心坐标

- **POST** `/manager/specimen-product-centers/create`
- **请求体**: `SpecimenProductCenterCreate`
- **说明**: 如果 stack_id 已存在则更新（upsert）
- **响应**: `SpecimenProductCenter`

### 6.2 根据 ID 获取中心坐标

- **GET** `/manager/specimen-product-centers/find/{center_id}`
- **路径参数**: `center_id` (int)
- **响应**: `{ error: bool, message: str, data: SpecimenProductCenter }`

### 6.3 根据 stack_id 获取中心坐标

- **GET** `/manager/specimen-product-centers/by-stack/{stack_id}`
- **路径参数**: `stack_id` (int)
- **响应**: `SpecimenProductCenter | null`

### 6.4 获取中心坐标列表

- **GET** `/manager/specimen-product-centers/list`
- **查询参数**:
  | 参数 | 类型 | 默认值 | 说明 |
  |------|------|--------|------|
  | skip | int | 0 | 偏移量 (>=0) |
  | limit | int | 100 | 每页数量 (<=1000) |
- **响应**: `{ centers: [...], total: int, skip: int, limit: int }`

### 6.5 更新中心坐标

- **PUT** `/manager/specimen-product-centers/update/{center_id}`
- **路径参数**: `center_id` (int)
- **请求体**: `SpecimenProductCenterUpdate`
- **响应**: `{ error: bool, message: str, data: SpecimenProductCenter }`

### 6.6 删除中心坐标

- **DELETE** `/manager/specimen-product-centers/del/{center_id}`
- **路径参数**: `center_id` (int)
- **响应**: `{ error: bool, message: str, data: {...} }`

---

## 7. 产品标记 (Specimen Product Markers)

**前缀**: `/manager/specimen-product-markers`  
**标签**: `specimen_product_markers`

### 7.1 创建标记

- **POST** `/manager/specimen-product-markers/create`
- **请求体**: `SpecimenProductMarkerCreate`
- **响应**: `SpecimenProductMarker`

### 7.2 根据 ID 获取标记

- **GET** `/manager/specimen-product-markers/find/{marker_id}`
- **路径参数**: `marker_id` (int)
- **响应**: `{ error: bool, message: str, data: SpecimenProductMarker }`

### 7.3 获取标记列表

- **GET** `/manager/specimen-product-markers/list`
- **查询参数**:
  | 参数 | 类型 | 必填 | 默认值 | 说明 |
  |------|------|------|--------|------|
  | stack_id | int | 是 | - | 堆叠 ID |
  | product_id | int | 否 | None | 产品 ID (0=获取全部) |
  | skip | int | 否 | 0 | 偏移量 (>=0) |
  | limit | int | 否 | 100 | 每页数量 (<=1000) |
- **响应**: `{ markers: [...], total: int, skip: int, limit: int }`

### 7.4 更新标记

- **PUT** `/manager/specimen-product-markers/update/{marker_id}`
- **路径参数**: `marker_id` (int)
- **请求体**: `SpecimenProductMarkerUpdate`
- **响应**: `{ error: bool, message: str, data: SpecimenProductMarker }`

### 7.5 删除标记

- **DELETE** `/manager/specimen-product-markers/del/{marker_id}`
- **路径参数**: `marker_id` (int)
- **响应**: `{ error: bool, message: str, data: {...} }`

---

## 8. 导航与数据生成 (Navigation)

**前缀**: `/manager/navigation`  
**标签**: `navigation`

### 8.1 生成当天数据并打包下载

- **POST** `/manager/navigation/generate-today-data`
- **说明**: 调用 Protobuf 数据合成脚本，生成当天的 `.pb` 和 `.json` 文件并打包为 ZIP 下载
- **响应**: ZIP 文件 (application/zip)

---

## 9. 统计 (Statistics)

**前缀**: `/manager/statistics`  
**标签**: `statistics`

### 9.1 获取瓦片统计数据

- **GET** `/manager/statistics/tile-counts`
- **查询参数**:
  | 参数 | 类型 | 默认值 | 说明 |
  |------|------|--------|------|
  | user_name | str | None | 按采集员过滤 |
  | start_date | str | None | 起始日期 (YYYY-MM-DD 或 YYYYMMDD) |
  | end_date | str | None | 结束日期 (YYYY-MM-DD 或 YYYYMMDD) |
- **说明**: 按 specimen_id + ratio_id + stack_id 分组统计瓦片数量，返回关联名称
- **响应**:
  ```json
  [
    {
      "specimen_id": 1,
      "specimen_name": "标本A",
      "ratio_id": 1,
      "ratio_name": "400x",
      "stack_id": 1,
      "stack_name": "stack-1",
      "tile_count": 25,
      "collector": "张三",
      "collection_date": "2026-06-10"
    }
  ]
  ```

---

## 10. 热点问题 (Hotspots)

**前缀**: `/manager/hotspots`  
**标签**: `hotspots`

### 10.1 获取热点问题列表

- **GET** `/manager/hotspots/questions`
- **查询参数**:
  | 参数 | 类型 | 默认值 | 说明 |
  |------|------|--------|------|
  | source | str | None | 按来源过滤 (如 "知乎", "头条") |
  | topic | str | None | 按标题模糊搜索 |
  | page | int | 1 | 页码 (>=1) |
  | page_size | int | 10 | 每页数量 (1-100) |
- **响应**:
  ```json
  {
    "data": [
      {
        "id": 1,
        "source": "知乎",
        "topic": "...",
        "content": "...",
        "rewrite_topic": "...",
        "update_time": "2026-06-10T12:00:00"
      }
    ],
    "pagination": {
      "current_page": 1,
      "page_size": 10,
      "total_count": 100,
      "total_pages": 10
    }
  }
  ```

### 10.2 导出热点问题到 Excel

- **GET** `/manager/hotspots/export_excel`
- **查询参数**: 同 10.1 的 source 和 topic
- **响应**: Excel 文件 (application/vnd.openxmlformats-officedocument.spreadsheetml.sheet)

---

## 11. 第三方接口 (API / Specimens Third)

**前缀**: `/api/specimens`  
**标签**: `specimens_third`

> 此模块接口支持加密传输 (通过 `enc` 查询参数控制)，默认 `enc=True`

### 11.1 健康检查

- **GET** `/api/specimens/status`
- **响应**: `{ status: "ok", message: "the server is running" }`

### 11.2 获取标本第三方信息

- **POST** `/api/specimens/third`
- **查询参数**: `enc` (bool, 默认 True) — 是否启用加密
- **请求体**: `SpecimenRequest`
  ```json
  {
    "third_id": "xxx",
    "ratio": "400",
    "stack_id": "1",
    "encrypted_data": "..."  // enc=True 时使用
  }
  ```
- **说明**: 根据第三方 ID、放大倍数、堆叠 ID 查询标本信息，返回瓦片产品和标记数据
- **响应 (enc=False)**:
  ```json
  {
    "code": 2000,
    "msg": "ok",
    "data": {
      "specimen_id": 1,
      "specimen_name": "...",
      "ratio_id": 1,
      "ratio_name": "...",
      "stack_id": 1,
      "light": 100,
      "light_circle": 0.5,
      "light_field": 1,
      "ruler": "...",
      "tile_products": [...],
      "markers": [...],
      "center": {...}
    }
  }
  ```
- **响应 (enc=True)**: 加密后的纯文本字符串

### 11.3 AI 问答（通用）

- **POST** `/api/specimens/question`
- **查询参数**: `enc` (bool, 默认 True)
- **请求体**: `QuestionRequest`
  ```json
  {
    "message": "什么是细胞？",
    "previous_response_id": "...",  // 多轮对话上下文
    "stream": true,
    "encrypted_data": "..."
  }
  ```
- **说明**: 通用 AI 问答，支持流式 (SSE) / 非流式输出，自动生成推荐问题
- **流式响应 (SSE)**:
  ```
  data: {"text": "细"}          // 文本片段
  data: {"recommend": [...]}    // 推荐问题
  data: {"completed":"true","response_id":"..."}  // 完成标记
  data: [DONE]
  ```
- **非流式响应**:
  ```json
  {
    "code": 2000,
    "msg": "ok",
    "data": {
      "text": "...",
      "recommend": [...],
      "response_id": "..."
    }
  }
  ```

### 11.4 AI 问答（标本相关）

- **POST** `/api/specimens/conversation`
- **查询参数**: `enc` (bool, 默认 True)
- **请求体**: `ConversationRequest`
  ```json
  {
    "message": "这个标本有什么特征？",
    "previous_response_id": "...",
    "stream": true,
    "specimen": "洋葱表皮细胞",  // 标本名称，限定对话范围
    "encrypted_data": "..."
  }
  ```
- **说明**: 仅限标本相关问题的 AI 问答，支持标本名称上下文，额外返回 AI 生成的标本配图
- **流式响应**: 同 11.3，但首个事件为 `{ "image": "https://..." }`
- **非流式响应**: 额外包含 `image` 字段

### 11.5 小说内容获取

- **POST** `/api/specimens/novel`
- **查询参数**: `enc` (bool, 默认 True)
- **请求体**: `NovelRequest`
  ```json
  {
    "novel_id": 1,
    "stream": true,
    "encrypted_data": "..."
  }
  ```
- **说明**: 获取小说章节内容，支持流式/非流式，自动推荐下一章和随机章节
- **流式响应 (SSE)**:
  ```
  data: {"novel_id":1,"title":"...","content":"...","is_pay":false}  // 分段内容
  data: {"recommend": [...]}                                          // 推荐章节
  data: {"completed":"true"}                                          // 完成标记
  data: [DONE]
  ```
