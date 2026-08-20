- # Dispatcher 架构升级说明

  > 适用读者：对本项目零基础的同学。读完这份文档，你应该能回答「这个服务是干什么的」「以前怎么做的」「为什么要改」「改成了什么样」「代价是什么」。
  >
  > 涉及代码：`yuanbao-group-dispatcher`
  > 时间跨度：2026-04-15 新框架首次落地 → 2026-05-20 旧代码全量下线（commit `a8d8444`）

  ---


  ## 1. 背景：这个服务在整条链路里的位置

  元宝的群聊和私聊消息走的是腾讯云 IM。用户在 App 里发一条消息，IM 落地后会通过回调把消息投递到 Kafka。**`yuanbao-group-dispatcher`（下称 dispatcher）就是这些 Kafka 消息的唯一消费方和分发中心。**

  它的职责可以概括成一句话：**把上游各个 topic 的消息解出来，先做完这条消息必须完成的加工，再扇出给所有关心这条消息的下游服务。**

  注意这里是**两件性质不同的事**，后面第 4 节会看到，新架构正是围绕这个区分来组织的：

  ```
                                        ┌──────────────────────┐
  用户 App ──▶ 腾讯云 IM ──▶ Kafka ──▶  │      dispatcher      │
                                        └───────────┬──────────┘
                                                    │
                  ┌─────────────────────────────────┴──────────────────────────────┐
                  │                                                                │
        ① 必须完成的加工（串行、失败即中断）                  ② 扇出通知（并发、尽力而为）
                  │                                                                │
          ┌───────┴────────┬──────────────┐              ┌─────────┬───────────┬────┴──────┐
          ▼                ▼              ▼              ▼         ▼           ▼           ▼
     会话存储服务      RAG 索引服务    过滤/撤回等    OpenClaw Proxy  群聊 Agent  私聊 Agent  搜索/事件类
     (消息落库)      (检索库写入)                  (第三方机器人)  (元宝智能体)          (群、活动等)
  ```

  **关键差别在于失败时会发生什么**：左边任何一步失败，这条消息就到此为止，右边一个都不会执行——因为消息都没落库成功，把半截数据推给机器人是有害的。右边则彼此独立，OpenClaw 挂了不影响 Agent。

  这个位置决定了它的两个特征：

  1. **它是扇出点。** 一条群消息可能同时要落库、要写检索库、要推给机器人、要送给 Agent。下游数量只会越来越多。
  2. **它是单点。** 它挂了或者变慢了，群聊里所有机器人和智能体都会失声。

  架构升级要解决的，正是「扇出点」这个身份带来的问题。

  ---

  ## 2. 老架构：一个 topic 一套代码

  ### 2.1 目录结构

  老代码集中在 `service_kafka/consumer/` 下，按 topic 分文件：

  ```
  service_kafka/consumer/
  ├── batch_consumer_base.go              # 通用批量消费骨架
  ├── batch_im_msg_consumer.go            # IM 消息 topic
  ├── batch_event_publish_msg_consumer.go # 事件发布 topic
  ├── batch_group_info_msg_consumer.go    # 群信息 topic
  ├── batch_user_info_msg_consumer.go     # 用户信息 topic
  ├── batch_activity_msg_consumer.go      # 活动 topic
  ├── event/
  │   └── event_msg_handler.go
  └── im/
      ├── group_msg_handler.go            # IM 消息的总路由（switch）
      ├── group_msg_after.go              # 群消息发送后
      ├── c2c_msg_after.go                # 私聊消息发送后
      ├── after_recall_group_msg.go       # 群消息撤回
      ├── after_recall_c2c_msg.go         # 私聊消息撤回
      ├── after_group_delete.go           # 群解散
      ├── after_new_member_join.go        # 新成员入群
      ├── after_member_exit.go            # 成员退群
      └── after_group_info_changed.go     # 群资料变更
  ```

  一共 5 个 topic，每个 topic 一套 `consumer + handler + processor`。

  ### 2.2 一条群消息的完整旅程

  以「用户在群里发了一条消息」为例，老链路是这样走的：

  **第一步，批量消费。** `BaseBatchConsumer.batchConsume` 一次拿到一批 Kafka 消息，逐条生成独立的 `ctx`（顺便把上游传来的调用链 ID 提取出来，方便日志串联），做反序列化，然后用 `trpc.GoAndWait` 并发处理整批——这个工具的作用是「起一批 goroutine 并等它们全部结束」，后面新架构也会反复用到。

  **第二步，按类型路由。** `GroupMsgHandler.Handle` 用一个 `switch` 把 8 种 IM 消息类型分发到 8 个 processor：

  ```go
  switch msgType {
  case uint32(imKafka.MsgType_GROUP_MSG_AFTER):
      return NewGroupMsgAfterProcessor(ctx, msgBody, msgAppSDKId, commParam).Process()
  case uint32(imKafka.MsgType_GROUP_MSG_WITHDRAW):
      return NewAfterRecallGroupMsgProcessor(ctx, msgBody).Process()
  case uint32(imKafka.MsgType_C2C_MSG_AFTER):
      return NewC2CMsgAfterProcessor(ctx, msgBody, msgAppSDKId, commParam).Process()
  // ... 另外 5 种
  default:
      return nil
  }
  ```

  **第三步，在一个函数里干完所有事。** `GroupMsgAfterProcessor.Process()` 是整条链路的核心，也是问题的集中地：

  ```go
  func (p *GroupMsgAfterProcessor) Process() error {
      // 1. 设置 env 元数据（测试环境路由用）
      if common.IsTestEnv() { trpc.SetMetaData(ctx, "selector-meta-env", ...) }
  
      // 2. 过滤：正在输入中的消息不处理
      if p.filterMessage(ctx) { return nil }
  
      // 3. 落库
      if err := p.saveMessage(ctx); err != nil { return err }
  
      // 4. 推给 OpenClaw（第三方机器人）
      err = p.sendToOpenClaw(ctx)
      if err != nil { ulog.Errorf(...) }          // 失败只打日志
  
      // 5. 推给群聊 Agent（元宝智能体）
      err = p.sendGroupDispatcherAgent(ctx)
      if err != nil { ulog.Errorf(...); return nil }  // ← 注意这个 return
  
      // 6. 发春节活动事件
      p.sendChunjieEvent(ctx, msg)                 // trpc.Go 异步，2s 超时
  
      // 7. 发红包群组事件
      p.sendRedPacketGroupEvent(ctx, msg)          // trpc.Go 异步，2s 超时
  
      return nil
  }
  ```

  ### 2.3 老架构是怎么「分发给多个下游」的

  **没有分发机制。** 所谓分发，就是在 `Process()` 里按代码顺序一行行写死调用。四个下游的调用方式各不相同：

  | 下游 | 同步/异步 | 超时 | 目标地址来源 | 重试 | 失败后果 |
  |---|---|---|---|---|---|
  | OpenClaw | 同步 | 5s，写死在函数里 | 硬编码字符串 | 无 | 打日志，继续 |
  | 群聊 Agent | 同步 | client 默认 | gateway 包封装 | 循环 3 次 + 100ms sleep | **`return nil`，掐断后两个** |
  | 春节事件 | `trpc.Go` | 2s | producer 包 | 无 | 打日志，无指标 |
  | 红包事件 | `trpc.Go` | 2s | producer 包 | 无 | 打日志，无指标 |

  OpenClaw 的调用长这样，注意目标地址直接写在业务函数体里：

  ```go
  proxy := ygp.NewYuanBaoGroupEventSubscribeServiceClientProxy(
      client.WithTarget("polaris://trpc.yuanbao.yuanbao-openclaw-proxy.trpc"),  // 硬编码
      client.WithNetwork("tcp"),
      client.WithProtocol("trpc"),
      client.WithTimeout(5*time.Second),                                        // 硬编码
  )
  ```

  ---

  ## 3. 老架构存在的问题

  ### 3.1 故障会在下游之间传染（最严重）

  看第 5 步那个 `return nil`：群聊 Agent 调用失败（重试 3 次仍失败）后直接返回，**春节事件和红包事件根本不会执行**。

  这两个下游和 Agent 在业务上毫无关系，纯粹因为写在后面而被连坐。更麻烦的是，这不是一个「改一行就好」的 bug——在「所有下游串在一个函数里」的形状下，任何人加一个带 `return` 的分支都会重新制造它，只能靠 code review 拦。

  ### 3.2 新增下游必须改代码、发版

  下游地址硬编码在业务函数里，接入一个新下游要：在 `Process()` 里插一行 → 写一个新方法 → 填 target 和超时 → 走发布流程。而下游数量是持续增长的，这条路注定越走越堵。

  反过来，**出问题时也没有止血手段**：某个下游开始大面积超时拖慢整体消费，只能紧急发版摘掉它。

  ### 3.3 监控靠每处手写，覆盖不全且容易漏

  需要先澄清一点：**老架构并非没有分段监控**。落库和 Agent 调用各自都有独立的耗时指标，写法是在方法里加一个 defer：

  ```go
  func (p *GroupMsgAfterProcessor) saveMessage(ctx context.Context) error {
      startTime := time.Now()
      var err error
      defer func() {
          errCode := zhiyan.GetMetricErrCode(err)
          _ = zhiyan.Report("SaveMessage", common.REPORT_API_TYPE_KAFKA_SAVE_MSG,
              errCode, startTime.UnixMilli())
      }()
      // ...
  }
  ```

  `sendGroupDispatcherAgent` 同样有 `SendGroupDispatcherAgent` 指标，还额外上报了重试次数；私聊侧对应的是 `SavePrivateMessage` 和 `SendC2CDispatcherAgent`。

  真正的问题是**这套上报完全依赖开发者自觉，因此覆盖是残缺的**。把老代码里所有上报点数一遍：

  | 环节 | 是否有独立指标 |
  |---|---|
  | 批量消费、单条处理、批大小、消费延迟 | 有（`BaseBatchConsumer` 统一做） |
  | 按消息类型的总耗时 `Handle_<MsgType>` | 有（`GroupMsgHandler` 统一做） |
  | 群消息落库 / 私聊消息落库 | 有 |
  | 群聊 Agent / 私聊 Agent（含重试次数） | 有 |
  | **OpenClaw 推送（群聊和私聊都是）** | **没有** |
  | **春节事件、红包事件** | **没有**，`trpc.Go` 里失败只打日志 |
  | **另外 6 种 IM 消息类型的处理内部** | **没有**，只有外层一个总耗时 |

  也就是说，四个下游里有两个（OpenClaw、两个 MQ 事件）在监控上是完全的盲区。OpenClaw 是对接第三方机器人的核心链路，却恰好是没有指标的那个——出问题时只能翻日志。

  所以这一条的准确表述不是「做不到分段」，而是：**分段上报的义务落在每个函数作者身上，只要有人忘了写，那一段就是黑的，而且没有任何机制会提醒他。**

  ### 3.4 重复代码成倍增长

  5 个 topic 各自一套 consumer，8 个 IM processor 各自一套逻辑，而其中有一批事情是每份都要重写的：把消息体反序列化、设置测试环境路由用的元数据（`selector-meta-env`，用来把测试流量导到指定的服务实例）、拼装监控维度、组织日志格式。加一个 topic 就要再抄一遍。

  ### 3.5 无法测试

  `sendToOpenClaw` 把 target 硬编码在函数体里，没有任何注入点；`Process()` 内部直连 5 个外部服务。这类代码写不出有意义的单元测试，改动只能靠上线验证。

  ### 3.6 职责边界模糊

  「消息必须成功落库」和「消息尽量推给机器人」是两种完全不同的可靠性要求，但在老代码里它们是同一个函数里相邻的两行，没有任何机制体现这个差别。落库失败 `return err`、OpenClaw 失败 `return nil` 的区分完全靠人肉记忆。

  ---

  ## 4. 新架构：一条流水线，两类角色

  ### 4.1 核心设计：把下游拆成 Processor 和 Subscriber

  新架构最重要的一个决定，是把「消息处理」明确切成两类语义完全不同的角色：

  | | **Processor（处理器）** | **Subscriber（订阅者）** |
  |---|---|---|
  | 定位 | 消息本身的必要加工 | 通知外部关心这条消息的人 |
  | 例子 | 丢弃「对方正在输入」这类无需处理的消息、消息落库、处理撤回、存事件、写 RAG 检索库 | 推给 OpenClaw、调群聊/私聊 Agent、写群和活动的搜索索引 |
  | 执行方式 | 按配置顺序**串行** | **并发**扇出 |
  | 失败语义 | 中断链路，**不再往下扇出** | 只记录该订阅者失败，**其余照常** |
  | 一句话 | 数据一致性优先 | 尽力而为（best-effort） |

  有了这个划分，「Agent 挂了带走红包事件」在结构上就不可能发生；反过来，「消息没存成功却把半截数据推给了下游」也不会发生。

  ### 4.2 三段式流水线

  所有 topic 现在共用同一条流水线：

  ```
  Kafka 一批消息
        │
        ▼
   ┌─────────────────────────────────────────────────────────┐
   │ Dispatch          按 source 配置选择 parallel /          │
   │                   serial_by_key（按 key 保序）           │
   └────────────────────────┬────────────────────────────────┘
                            │ 每条消息
                            ▼
   ┌─────────────────────────────────────────────────────────┐
   │ ① Decode    按 source 找 Decoder → 统一的 Message 实体   │
   │             同时上报消费量、消费延迟、解码失败            │
   ├─────────────────────────────────────────────────────────┤
   │ ② Process   原始 MsgType → 统一 EventType                │
   │             按配置的 Processor 名单顺序执行               │
   │             任一失败 → 中断，不进入 Publish               │
   ├─────────────────────────────────────────────────────────┤
   │ ③ Publish   EventBus 按 EventType 查订阅者列表            │
   │             → 按 Target 去重 → GoAndWait 并发扇出         │
   │             每个订阅者独立上报耗时与错误                  │
   └─────────────────────────────────────────────────────────┘
  ```

  对应代码在 `internal/domain/dispatcher/`：

  ```
  internal/domain/dispatcher/
  ├── dispatcher.go             # Dispatch：parallel / serial_by_key
  ├── dispatcher_kafka.go       # 路由 + 各 source 的 Process 实现
  ├── dispatcher_kafka_base.go  # Decode / Process / Publish 三段骨架
  ├── decoder.go                # source → Decoder 注册表
  ├── source/source.go          # 6 个 source 常量
  ├── processors/               # 8 个 Processor + 注册表
  └── subscriber/
      ├── subscriber.go         # 13 种订阅者类型注册表
      ├── loader.go             # 从 Rainbow 实时加载订阅者
      ├── eventbus.go           # 去重 + 并发扇出
      ├── im/ group/ user/ activity/ event/   # 各类订阅者实现
  ```

  ### 4.3 各阶段细节

  **① Decode——统一入口。** 各个 source 从 Kafka 拿到的都是一段原始字节，而且序列化方式还不一样（有的是 Protobuf、有的是 JSON、IM 甚至是 Protobuf 套 JSON）。6 个 source 各自注册一个 Decoder，把这些字节统一解成同一个 `entity.Message` 结构，后续所有环节只面对结构体。

  这一层还统一做了三件老架构分散在各处的事：上报消费量和 Kafka 消费延迟、打入口日志、解码失败上报。

  **② Process——归一化 + 必做动作。** 先把各 source 的原始类型映射成统一的 `EventType`（比如 IM 的 `GROUP_MSG_AFTER` → `EVENT_TYPE_IM_GROUP_MSG_SEND`），未知类型直接跳过；再按 Rainbow 配置的名单顺序执行 Processor。

  目前注册了 8 个 Processor：

  ```go
  var processors = map[string]Processor{
      "ActivityDetailProcessor": &ActivityDetailProcessor{},
      "ImFilterProcessor":       &ImFilterProcessor{},   // 过滤"正在输入中"
      "ImSaveEventProcessor":    &ImSaveEventProcessor{},
      "GroupMsgSaveProcessor":   &GroupMsgSaveProcessor{},
      "GroupMsgRecallProcessor": &GroupMsgRecallProcessor{},
      "C2CMsgSaveProcessor":     &C2CMsgSaveProcessor{},
      "C2CMsgRecallProcessor":   &C2CMsgRecallProcessor{},
      "rag_index":               &RagIndexProcessor{},
  }
  ```

  Processor 的返回值是 `(shouldContinue bool, err error)`，三种组合分别表示：正常继续、主动跳过（不算错误）、失败中断。

  > **一个容易看混的地方：「写索引」这件事在两边都有，但不是同一个东西。**
  > `rag_index` 是 **Processor**——RAG 检索库的写入被定为必做动作，`IndexGroupChat` 之类的 RPC 失败会中断链路、不再扇出。
  > 而 `GroupSearchSubscriber`、`ActivitySearchSubscriber` 等是 **Subscriber**——群、活动、群成员的搜索索引属于尽力而为，失败不影响别人。
  > 判断依据不是「它是不是写索引」，而是「这一步失败后，把消息继续推给下游还有没有意义」。

  > 注意一个容易踩的差异：老架构的春节事件、红包事件两个下游**没有被迁移过来，而是随业务下线一起删掉了**。IM 侧当前只有 3 个订阅者（OpenClaw / 群聊 Agent / 私聊 Agent）。如果你在 `2026-04-10-im-event-migration-design.md` 里看到 `imChunjieSubscriber`、`imRedPacketSubscriber`，那是设计当时的规划，代码里已不存在。

  **③ Publish——去重并发扇出。** `EventBus.Publish` 的逻辑很短，但每一行都在解决老架构的一个问题：

  ```go
  subscribers, err := e.loader.Load(ctx, msg.EventType)  // 从配置查，不是写死
  subscribers = e.deduplicateSubscribers(subscribers)     // 按 Target 去重，防重复推送
  
  for _, sub := range subscribers {
      fns = append(fns, func() error {
          err := sub.Handle(ctx, msg)
          e.handleResult(ctx, sub, msg, costMs, err)      // 每个订阅者独立上报
          return nil                                       // ← 永远返回 nil，错误不外溢
      })
  }
  return trpcgo.GoAndWait(fns...)                          // 并发，等齐
  ```

  那句 `return nil` 是故障隔离的物理保证：一个订阅者的错误在类型上就没有路径影响到另一个订阅者。

  ### 4.4 配置驱动

  订阅者列表放在 Rainbow，每条配置长这样：

  ```json
  {
    "name": "imOpenClawSubscriber",
    "subscribe_type": "imOpenClawSubscriber",
    "target": "polaris://trpc.yuanbao.yuanbao-openclaw-proxy.trpc",
    "timeout": 5000,
    "event_type_map": {
      "<群消息发送的 EventType 整数值>": "群聊OpenClaw",
      "<私聊消息发送的 EventType 整数值>": "私聊OpenClaw"
    }
  }
  ```

  `event_type_map` 的 key 是 `pb.EventType` 枚举的**整数值**，value 只是给人看的注释，代码不读。改配置前请以当时 proto 里的实际枚举值为准，不要照抄文档里的数字。

  `ConfigLoader` 每次 Publish 都实时读配置，因此**改配置立即生效，无需重启**。

  这里有一个刻意的容错设计：如果配置里出现了代码还不认识的 `subscribe_type`，loader 会打错误日志并跳过它，而不是让整条消息失败——这样「先改配置、后发代码」的操作顺序不会引发故障。

  ```go
  sub, err := NewSubscriber(cfg)
  // 忽略配置中不存在的订阅者，避免因为配置错误导致整个流程失败
  if err != nil {
      log.ErrorContextf(ctx, "[ConfigLoader] NewSubscriber failed: ...")
      continue
  }
  ```

  ### 4.5 消费模式：并发与保序

  `Dispatch` 支持两种模式，按 source 在配置里选：

  - **`parallel`（默认）**：整批消息每条起一个 goroutine 并发跑，等全部结束。吞吐优先，不保证处理顺序。
  - **`serial_by_key`**：按 Kafka 消息的 key 分组，**同一个 key 的消息严格按顺序一条条处理，不同 key 之间仍然并发**。订单类事件（`mt_order`）用的就是这个模式——同一笔订单的「创建、支付、完成」如果乱序处理，状态就错了。

  `serial_by_key` 能保证跨批次也有序，依赖两个前提：生产端按 key 分区（同 key 的消息一定落在同一个分区），以及 trpc-kafka「批处理函数返回前不会拉下一批」的特性。

  老架构只有整批无差别并发，没有保序能力。

  ---

  ## 5. 新架构带来了什么

  这次改造顺带产生的好处很多，但真正**在日常和故障中能被明显感知**的只有三条。下面每一条都配一个具体场景——如果你没经历过这些场景，很难体会到差别在哪。

  其余改进统一放在 5.4 一笔带过，它们是真实的，但没到需要展开的程度。

  ---

  ### 5.1 一个下游出问题，不会再连累其他下游

  **老架构下这个故障长什么样。**

  假设某天群聊 Agent 的服务抖动，调用超时。按老代码的写法，`sendGroupDispatcherAgent` 重试 3 次仍失败后执行 `return nil`，于是排在它后面的春节事件和红包事件**一条都发不出去**。

  要命的是这个故障的表现形式：

  - 用户侧看到的现象是「群里发消息不掉红包了」；
  - 但红包事件根本没有监控指标（见 3.3 那张表），仪表盘上一切正常；
  - 排查的人从「红包不掉」这个现象，几乎不可能联想到「是 Agent 在抖」。

  **这不是写错了一行，而是这个形状必然会长出这种问题。** 所有下游串在一个函数里，任何人后续加一个带 `return` 的分支，都会重新制造一次同样的连累关系，唯一的防线是 code review 有没有看出来。

  **新架构下为什么不可能发生。**

  `EventBus` 扇出时，给每个订阅者包了一层闭包，而这个闭包**永远返回 `nil`**：

  ```go
  fns = append(fns, func() error {
      err := sub.Handle(ctx, msg)          // 订阅者自己的错误
      e.handleResult(ctx, sub, msg, costMs, err)  // 只进监控
      return nil                            // ← 错误到此为止，不外溢
  })
  return trpcgo.GoAndWait(fns...)
  ```

  一个订阅者的失败在**类型层面**就没有路径影响到另一个订阅者。这不是「我们注意不要写错」，是「想写错都写不出来」。

  **顺带解决的一个理解问题。** 老代码里，「落库失败要 `return err`」和「OpenClaw 失败要 `return nil`」的区别完全靠人记忆，没有任何东西提示你该用哪个。新架构把这个判断变成了一道选择题：**这一步失败之后，把消息继续推给下游还有没有意义？** 有意义就是 Subscriber，没意义就是 Processor。选对角色，失败语义自动就对了。

  ---

  ### 5.2 出故障时，能直接看出是哪个下游的问题

  **老架构下的排查过程。** 用户反馈「群里 @ 机器人不回复了」，你打开监控，能看到的只有：批量消费量、单条处理总耗时、`Handle_GROUP_MSG_AFTER` 的总耗时，以及落库和 Agent 的耗时。

  而 OpenClaw——也就是第三方机器人这条链路本身——**没有任何指标**。你无法回答「是我们没推过去，还是推过去了对方没回」，只能去日志里捞。

  **新架构为什么不会再出现盲区。** 关键不在于「有了分段指标」（老架构也有），而在于**上报这件事从"每个作者自己写"变成了"框架统一做"**：

  ```go
  fns = append(fns, func() error {
      startAt := time.Now()
      err := sub.Handle(ctx, msg)
      costMs := float64(time.Since(startAt).Milliseconds())
      e.handleResult(ctx, sub, msg, costMs, err)   // → ReportSubscribeResult
      return nil
  })
  ```

  任何订阅者，只要挂到 `EventBus` 上，就自动拥有独立的耗时、成功率、错误码，**订阅者的作者一行监控代码都不用写**。老架构里 OpenClaw 那种「核心链路却恰好没人记得加指标」的情况，在结构上不会再发生。

  同样的思路贯穿整条流水线，现在的指标是分层的：

  | 指标 | 关键维度 | 回答什么问题 |
  |---|---|---|
  | `ReportConsume` | source, topic | 消息进来了吗？Kafka 堆积多久了？ |
  | `ReportDecodeFail` | topic | 上游是不是改协议了？ |
  | `ReportDispatchResult` | source, **stage** | 卡在解码、处理、还是扇出？ |
  | `ReportSubscribeResult` | source, **subscriber** | 具体哪个下游在慢、在报错？ |

  其中 `stage` 也不需要手写——用一个 `stageError` 包装类型在三段之间自动标注：

  ```go
  msg, err := dispatcher.Decode()
  if err != nil { return newStageErr("decode", err) }
  shouldPublish, err := dispatcher.Process(ctx, msg)
  if err != nil { return newStageErr("process", err) }
  if err = dispatcher.Publish(ctx, msg); err != nil { return newStageErr("publish", err) }
  ```

  这条收益平时体会不到，只在**故障的头十分钟**兑现：「所有环节默认可见」和「大部分环节可见、恰好出事的那个不可见」，是完全不同的两种体验。

  ---

  ### 5.3 调整下游不用发版，紧急情况能立刻止血

  **先说为什么需要止血。** 新架构的扇出是并发**同步**的——一条消息要等所有订阅者都返回才算处理完。所以某个下游从 50ms 劣化到 5s 时，后果不只是它自己慢，而是**整个 Kafka 消费速度被它拖住**，堆积上涨，最后群里所有机器人和智能体一起变慢。

  **老架构遇到这种情况怎么办：** 改代码、走发布流程。从决定止血到生效，十几分钟起步。

  **新架构怎么办：** 把这个订阅者从 Rainbow 配置的 `event_type_map` 里摘掉。`ConfigLoader` 每次扇出都实时读配置，**改完秒级生效**，不用发版、不用重启。

  ```go
  // 每次 Publish 都重新 Load，所以配置改动立即反映到下一条消息
  subscribers, err := e.loader.Load(ctx, msg.EventType)
  ```

  **顺带说说「接入新下游」这件事——它经常被高估，需要准确表述。** `subscribe_type` 必须在代码里注册过，配置才认，所以要分两种情况：

  - 新下游只需要「用标准结构调一个 tRPC 方法」或「往 Kafka 发一条消息」——用现成的 `rpc` / `rpc:v2` / `kafka` 类型，**纯改配置，不发版**。
  - 新下游需要定制逻辑（比如 OpenClaw 要按消息类型映射成四种事件、私聊还要按账号前缀做过滤）——**照样要写代码、注册类型、发版**。

  所以真实收益是「不再把目标地址和超时硬编码在业务函数里」，不是「零代码接入」。

  ---

  ### 5.4 其余一并拿到的改进

  这些是真实的收益，但日常感知不强，简单列一下：

  - **6 个 source 共用一条流水线。** IM 消息、IM 事件发布、订单事件、用户信息变更、活动事件、群信息变更，现在都走同一条 `Decode → Process → Publish`。老架构是每个 topic 一套骨架，解码、调用链透传、环境元数据、监控上报各写一遍——删掉的是成倍的重复代码，不只是一个 switch。
  - **单条消息的扇出延迟下降。** 从串行调用变成并发，总耗时从「所有下游累加」变成「最慢的那一个」。
  - **具备了按 key 保序的能力。** 老架构只能整批无差别并发；新架构的 `serial_by_key` 模式可以做到组内严格有序、组间并发，订单类事件依赖这个能力。
  - **代码可以写测试了。** 老代码把目标地址写死在函数体里、内部直连五个外部服务，没有任何注入点。现在 `NewSubscriber`、`EventBus`、各 Decoder、各 Processor 都有单元测试。

  ---

  ## 6. 代价与风险

  新架构不是纯赚。下面三条是**接手这个项目后大概率会亲自撞上**的，值得展开讲；末尾再补一条容易忽略的小陷阱。

  ---

  ### 6.1 光读代码已经看不出消息去了哪里

  **老架构有一个常被忽视的优点：链路是自解释的。** 打开 `GroupMsgAfterProcessor.Process()` 从头读到尾，四个下游依次列在那里，不需要任何外部信息就知道这条消息会去哪。

  **新架构做不到这一点。** 你打开 `subscriber_im_openclaw.go`，只能知道「如果这个订阅者被调用了，它会做什么」；至于**它到底会不会被调用、对哪些事件类型生效**，答案不在代码里，在 Rainbow 配置的 `event_type_map` 中。

  具体影响是这样的：

  - 新人问「群消息现在发给哪几个下游」，正确的回答方式是**去查配置**，而不是读代码——这一点如果没人提前告知，很容易得出错误结论。
  - 排查一条消息的完整路径，要跨 `Dispatch → Decode → Process → Processor 链 → EventBus → Subscriber` 六层，而老架构基本是一个函数看到底。

  这是这次改造**最直接的一笔交易：用代码的自解释性，换来了运行时的可调整性。** 5.3 里那个「秒级止血」的能力，和这里的「读代码看不出去向」，本质上是同一个设计带来的一体两面。

  ---

  ### 6.2 配置写错不会报错，只会安静地什么都不做（最危险的一条）

  这是目前最容易踩、也最难排查的问题，**强烈建议接手的同学优先了解**。

  新架构里，「这条消息该做什么、该发给谁」全部来自配置查表。而两处查表在**查不到时都不算错误**：

  ```go
  // 查不到 Processor 名单 → 返回 nil
  func GetProcessorNames(source string, eventType pb.EventType) []string {
      // ... 命中不了就 return nil
  }
  // 空名单在 runProcessors 里会顺利跑完，返回"继续"
  
  // 查不到订阅者 → 返回空列表
  if len(subscribers) == 0 {
      log.WarnContextf(ctx, "no subscribers for eventType %q", msg.EventType)
      return nil   // ← 不是错误
  }
  ```

  **于是当 EventType 填错、或者配置漏配时，实际发生的是：** 消息被正常消费、正常解码、判定为处理成功，然后什么都不做，悄悄结束。

  这个失败形态之所以危险，是因为**它在监控上完全看不出来**：消费量正常、成功率 100%、没有任何错误码。排查的人看到「dispatcher 一切正常」，最自然的推论是「上游没发消息」，方向从一开始就错了。

  **有一个现实场景正好会触发它。** IM 事件在迁移设计阶段用了 4001、4002 这类临时数字作为 EventType 占位，配置也按这些数字下发；后来代码改用了正式枚举（`EVENT_TYPE_IM_GROUP_MSG_SEND` 等），**枚举的实际整数值和当初的占位值不一定一致**。线上配置如果没跟着更新，表现就是「明明配了，却一点动静都没有」。

  **目前可用的排查手段**（在补上告警之前）：`EventBus.Publish` 每次都会打印本次命中的订阅者名称和 target，一条都没命中时会有 `no subscribers for eventType` 的 WARN。改完 EventType 相关配置后，建议立刻用这条日志确认是否真的命中。

  **建议：给「查表为空」补一个独立的监控指标和告警。** 这是当前架构最明显的一处缺口。

  ---

  ### 6.3 某个下游变慢，会直接拖慢整体消费

  老架构里，春节和红包事件是 `trpc.Go` 异步发出去的——发了就忘，不占主流程时间；坏处是失败完全不可见（这正是 3.3 里那两个盲区的由来）。

  新架构统一改成了**并发但同步**：一条消息要等所有订阅者都返回才算处理完，单条耗时等于「最慢的那个订阅者」。

  这笔交换的两面很清楚：

  - **拿到的**：每个下游的成功率和耗时都可见、可告警（5.2）。
  - **付出的**：某个下游从 50ms 劣化到 5s，会立刻反映成 Kafka 消费速度下降、消息堆积，进而影响到**所有**业务，而不只是那一个下游。

  所以 5.3 那个「改配置摘掉下游」的止血手段不是锦上添花，**是这个设计的必要配套**。运维预案里应该包含它。
