"""Compile the implementation-depth policy for prototype and product builds."""

from __future__ import annotations

import hashlib
import json
from typing import Any


POLICY_SCHEMA_VERSION = 1
POLICY_VERSION = 1
VALID_TARGET_KINDS = {"prototype", "product"}


def _canonical_json(value: object) -> bytes:
    return json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")


def delivery_policy_for(target_kind: str) -> dict[str, Any]:
    """Return the frozen implementation-depth policy for one build target."""

    if target_kind not in VALID_TARGET_KINDS:
        raise ValueError(f"未知 build target：{target_kind}")
    if target_kind == "prototype":
        return {
            "schema_version": POLICY_SCHEMA_VERSION,
            "policy_version": POLICY_VERSION,
            "target_kind": "prototype",
            "implementation_mode": "interactive-simulation",
            "principle": "规格决定最终产品语义；本合同决定本轮实现深度。",
            "must_deliver": [
                "用户可见的主路径、相关页面、弹窗或抽屉、关键状态和操作反馈必须可交互",
                "权限差异、错误结果和异步结果必须以确定性的演示行为呈现",
            ],
            "simulate_by_default": [
                "数据持久化与数据库",
                "后端接口与异步任务",
                "鉴权、权限校验与审计",
                "外部系统集成、AI 引擎、通知与其它有副作用能力",
            ],
            "allowed_support": [
                "fixture、内存状态、localStorage 和仓内 mock adapter",
                "只服务演示且无真实外部副作用的本地 stub",
            ],
            "forbidden_without_decision": [
                "生产数据库、schema 或 migration",
                "真实鉴权、权限执行和生产账号体系",
                "真实外部写入、密钥接入和不可逆副作用",
                "生产基础设施、部署编排和迁移兼容代码",
            ],
            "required_check": "prototype-boundary",
        }
    return {
        "schema_version": POLICY_SCHEMA_VERSION,
        "policy_version": POLICY_VERSION,
        "target_kind": "product",
        "implementation_mode": "production-implementation",
        "principle": "规格决定最终产品语义；真实产品必须端到端实现已确认能力。",
        "must_deliver": [
            "用户可见行为与真实接口、数据、权限和兼容行为保持一致",
            "涉及迁移、安全或外部副作用时完成对应生产检查",
        ],
        "simulate_by_default": [],
        "allowed_support": ["仓库既有测试 fixture 和测试替身"],
        "forbidden_without_decision": [],
        "required_check": None,
    }


def validate_delivery_policy(policy: object, target_kind: str) -> dict[str, Any]:
    """Fail closed when a stored policy no longer matches its declared target."""

    if not isinstance(policy, dict):
        raise ValueError("build.delivery_policy 必须是对象。")
    expected = delivery_policy_for(target_kind)
    if policy != expected:
        raise ValueError(
            "build.delivery_policy 与当前 target 或 policy version 不一致；"
            "请回到 build 重新生成实现深度合同。"
        )
    return expected


def delivery_policy_hash(policy: object) -> str:
    return hashlib.sha256(_canonical_json(policy)).hexdigest()
