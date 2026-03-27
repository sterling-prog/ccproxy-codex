"""Default model metadata and mapping rules for the Codex provider.

Models mirror the 8 registered in the OpenClaw gateway (openclaw.json).
Context windows: gpt-5.3-codex-spark = 128K, all others = 272K.
The `id` field must match the gateway's model id exactly (P124 spec invariant).
"""

from __future__ import annotations

from ccproxy.models.provider import ModelCard, ModelMappingRule

# Shared creation timestamp (approx 2026-03-26)
_CREATED = 1774564347

DEFAULT_CODEX_MODEL_CARDS: list[ModelCard] = [
    ModelCard(
        id="gpt-5.4",
        created=_CREATED,
        owned_by="openai",
        permission=[],
        root="gpt-5.4",
        parent=None,
        context_window=272000,
    ),
    ModelCard(
        id="gpt-5.4-mini",
        created=_CREATED,
        owned_by="openai",
        permission=[],
        root="gpt-5.4-mini",
        parent=None,
        context_window=272000,
    ),
    ModelCard(
        id="gpt-5.3-codex",
        created=_CREATED,
        owned_by="openai",
        permission=[],
        root="gpt-5.3-codex",
        parent=None,
        context_window=272000,
    ),
    ModelCard(
        id="gpt-5.3-codex-spark",
        created=_CREATED,
        owned_by="openai",
        permission=[],
        root="gpt-5.3-codex-spark",
        parent=None,
        context_window=128000,  # Spark capped at 128K per P124 spec invariant
    ),
    ModelCard(
        id="gpt-5.2-codex",
        created=_CREATED,
        owned_by="openai",
        permission=[],
        root="gpt-5.2-codex",
        parent=None,
        context_window=272000,
    ),
    ModelCard(
        id="gpt-5.2",
        created=_CREATED,
        owned_by="openai",
        permission=[],
        root="gpt-5.2",
        parent=None,
        context_window=272000,
    ),
    ModelCard(
        id="gpt-5.1-codex-max",
        created=_CREATED,
        owned_by="openai",
        permission=[],
        root="gpt-5.1-codex-max",
        parent=None,
        context_window=272000,
    ),
    ModelCard(
        id="gpt-5.1-codex-mini",
        created=_CREATED,
        owned_by="openai",
        permission=[],
        root="gpt-5.1-codex-mini",
        parent=None,
        context_window=272000,
    ),
]


DEFAULT_CODEX_MODEL_MAPPINGS: list[ModelMappingRule] = [
    # Exact matches for all 8 gateway models (highest priority)
    ModelMappingRule(match="gpt-5.4", target="gpt-5.4", kind="exact"),
    ModelMappingRule(match="gpt-5.4-mini", target="gpt-5.4-mini", kind="exact"),
    ModelMappingRule(match="gpt-5.3-codex", target="gpt-5.3-codex", kind="exact"),
    ModelMappingRule(match="gpt-5.3-codex-spark", target="gpt-5.3-codex-spark", kind="exact"),
    ModelMappingRule(match="gpt-5.2-codex", target="gpt-5.2-codex", kind="exact"),
    ModelMappingRule(match="gpt-5.2", target="gpt-5.2", kind="exact"),
    ModelMappingRule(match="gpt-5.1-codex-max", target="gpt-5.1-codex-max", kind="exact"),
    ModelMappingRule(match="gpt-5.1-codex-mini", target="gpt-5.1-codex-mini", kind="exact"),
    # Fallback prefix rules → default to gpt-5.4 (latest)
    ModelMappingRule(match="gpt-5-codex", target="gpt-5.4", kind="prefix"),
    ModelMappingRule(match="gpt-", target="gpt-5.4", kind="prefix"),
    ModelMappingRule(match="o3-", target="gpt-5.4", kind="prefix"),
    ModelMappingRule(match="o1-", target="gpt-5.4", kind="prefix"),
    ModelMappingRule(match="claude-", target="gpt-5.4", kind="prefix"),
]


__all__ = [
    "DEFAULT_CODEX_MODEL_CARDS",
    "DEFAULT_CODEX_MODEL_MAPPINGS",
]
