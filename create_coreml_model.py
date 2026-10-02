#!/usr/bin/env python3
"""
create_coreml_model.py

Production-oriented reference pipeline for a small on-device notification model.

Architecture:
  1) DistilBERT sequence classifier -> Core ML .mlpackage
  2) Lightweight deterministic extractive/action-item summarizer

Why not Qwen2.5-1.5B -> Core ML in this script?
  A causal LLM is a generative decoder with KV-cache/state and autoregressive
  token generation. coremltools' generic PyTorch conversion + post-training
  weight quantization does not, by itself, create a complete tokenizer +
  autoregressive text-generation Core ML pipeline. For a notification router
  on a 16 GB Mac, a fine-tuned encoder classifier is substantially smaller,
  easier to validate, and easier to ship in an iOS notification extension.

The classifier accepts token IDs + attention mask, not raw String. Tokenization
is deliberately kept outside the neural graph so the same tokenizer can be
used in Python and Swift.

Expected artifact:
    NotificationClassifier.mlpackage

The .mlpackage contains:
    - classLabel: predicted category
    - classLabel_probs: probability dictionary

Note: passing a ClassifierConfig makes coremltools consume the network's
final "logits" output as the softmax source for classLabel_probs, so a
separate raw "logits" output is not present in the saved package.

The summarizer in this file is intentionally deterministic. It is designed
for notification/action-item extraction rather than open-ended generation.
Replace it with a separately converted seq2seq model only if you have a
real requirement for generative summaries.
"""

from __future__ import annotations

import json
import os
import random
import re
import shutil
import sys
from pathlib import Path
from typing import List, Tuple

import numpy as np
import torch
import coremltools as ct
import coremltools.optimize as cto
from transformers import (
    AutoTokenizer,
    AutoModelForSequenceClassification,
    get_linear_schedule_with_warmup,
)

# -----------------------------
# Configuration
# -----------------------------

MODEL_NAME = "distilbert-base-uncased"
OUTPUT_DIR = Path("NotificationClassifier.mlpackage")
HF_CACHE_DIR = Path.home() / ".cache" / "huggingface"

LABELS = [
    "Work",
    "Social",
    "Finance",
    "Security",
    "Promotional",
    "Personal",
]
LABEL2ID = {label: i for i, label in enumerate(LABELS)}
ID2LABEL = {i: label for label, i in LABEL2ID.items()}

MAX_LENGTH = 256
MIN_LENGTH = 1

# Keep training deliberately small for a 16 GB Apple Silicon machine.
EPOCHS = 3
BATCH_SIZE = 8
LEARNING_RATE = 2e-5
WEIGHT_DECAY = 0.01
SEED = 42

# Set to 4 for smallest artifact, or 8 for a conservative accuracy baseline.
QUANT_BITS = 4

# Minimum deployment target for blockwise INT4 weight compression.
MIN_IOS_TARGET = ct.target.iOS18

DEVICE = torch.device(
    "mps"
    if torch.backends.mps.is_available()
    else "cpu"
)


# -----------------------------
# Reproducibility / memory
# -----------------------------

def set_seed(seed: int = SEED) -> None:
    random.seed(seed)
    np.random.seed(seed)
    torch.manual_seed(seed)
    if torch.cuda.is_available():
        torch.cuda.manual_seed_all(seed)


def print_environment() -> None:
    print(f"Python:   {sys.version.split()[0]}")
    print(f"PyTorch:  {torch.__version__}")
    print(f"CoreML:   {ct.__version__}")
    print(f"Device:   {DEVICE}")
    print(f"Quant:    INT{QUANT_BITS}")


# -----------------------------
# Small bootstrap dataset
# -----------------------------
# IMPORTANT:
# This dataset is only a runnable bootstrap. For production accuracy, replace
# it with your real anonymized notification corpus and retrain/evaluate.

TRAINING_EXAMPLES = {
    "Work": [
        "Your meeting with the product team starts at 10 AM.",
        "New email from your manager about the project.",
        "Jira issue APP-409 is assigned to you.",
        "Slack: Alex mentioned you in the engineering channel.",
        "Your work calendar has been updated.",
        "Stand-up meeting begins in 15 minutes.",
        "The deployment pipeline finished successfully.",
        "Review requested for pull request #421.",
        "Your colleague shared a document with you.",
        "Microsoft Teams: You have a new work message.",
        "The sprint planning meeting was moved to 3 PM.",
        "Your timesheet is due today.",
        "New comment on the design document.",
        "GitHub: You were assigned a pull request.",
        "The production build is ready for review.",
        "Your work presentation is scheduled for tomorrow.",
        "The engineering team posted a new announcement.",
        "Your manager sent you a message.",
        "Work calendar reminder: client call at 4 PM.",
        "The CI build failed and needs attention.",
    ],
    "Social": [
        "Priya liked your photo.",
        "You have a new Instagram message.",
        "Rahul mentioned you in a post.",
        "You have a new friend request.",
        "Someone commented on your post.",
        "Your friend shared a new story.",
        "You have a new WhatsApp message.",
        "A group chat has 12 unread messages.",
        "Someone tagged you in a photo.",
        "Your friend is inviting you to an event.",
        "New reaction to your message.",
        "Your social group has a new message.",
        "You received a Snapchat notification.",
        "Someone started following you.",
        "A friend sent you a voice message.",
        "New comment from Anu.",
        "Your community group posted an update.",
        "You have a new social media notification.",
        "A friend mentioned you.",
        "New message in your family group.",
    ],
    "Finance": [
        "Your bank account ending in 4092 was charged $42.50 at Starbucks. Tap to view transaction.",
        "Your debit card was charged $18.20.",
        "UPI payment of ₹850 was successful.",
        "Your salary was credited to your bank account.",
        "Credit card payment of ₹5,000 is due tomorrow.",
        "A transfer of ₹12,500 was received.",
        "Your bank balance has changed.",
        "ATM withdrawal of ₹2,000 was completed.",
        "Your credit card statement is ready.",
        "Payment of $120.00 was made using your card.",
        "Your UPI transaction failed.",
        "A refund of ₹450 was credited.",
        "Your account received a cash deposit.",
        "Your monthly loan EMI is due.",
        "A card transaction was declined.",
        "Your mutual fund SIP was processed.",
        "Your bank has sent a transaction alert.",
        "Your wallet balance was updated.",
        "A payment was received into your account.",
        "Your card was charged for an online purchase.",
    ],
    "Security": [
        "New login detected from Chrome on Mac.",
        "Your verification code is 184921.",
        "Two-factor authentication code requested.",
        "A new device signed into your account.",
        "Your password was changed successfully.",
        "Security alert: unusual sign-in detected.",
        "Confirm your identity to continue.",
        "Your account recovery email was updated.",
        "New login attempt blocked.",
        "Your security settings were changed.",
        "Authentication code requested for your account.",
        "Suspicious activity was detected.",
        "Your account has been locked after failed attempts.",
        "A new device was added to your account.",
        "Security verification is required.",
        "Someone attempted to access your account.",
        "Your passcode was changed.",
        "Login approval requested.",
        "Your account security alert needs attention.",
        "Confirm this sign-in attempt.",
    ],
    "Promotional": [
        "Flash sale: 50% off everything today.",
        "Use code SAVE20 for 20% off.",
        "Your exclusive shopping offer expires tonight.",
        "Buy one get one free this weekend.",
        "New arrivals are now available.",
        "Limited-time discount on selected products.",
        "Get ₹500 off your next order.",
        "Weekend sale starts now.",
        "Extra 30% off for members.",
        "Your coupon is waiting.",
        "Special offer just for you.",
        "Free delivery on orders over ₹999.",
        "Last chance to claim your discount.",
        "Shop now and save big.",
        "Limited-time promotional offer.",
        "You unlocked a new reward.",
        "Early access to our sale.",
        "Enjoy a special member discount.",
        "Holiday sale is live.",
        "Don't miss today's deal.",
    ],
    "Personal": [
        "Your package will arrive today.",
        "Your food delivery is arriving soon.",
        "Your cab driver has arrived.",
        "Your appointment is tomorrow at 11 AM.",
        "Reminder: dentist appointment at 5 PM.",
        "Your electricity bill is due tomorrow.",
        "Your grocery order is ready for delivery.",
        "Your flight check-in is now open.",
        "Your parcel was delivered.",
        "Your hotel booking is confirmed.",
        "Your train ticket is confirmed.",
        "Your prescription is ready for pickup.",
        "Your utility bill was paid.",
        "Your ride has reached the pickup location.",
        "Your order is out for delivery.",
        "Reminder: pay your monthly utility bill.",
        "Your reservation is confirmed.",
        "Your delivery partner is nearby.",
        "Your personal appointment has been rescheduled.",
        "Your travel booking has been updated.",
    ],
}


def build_dataset() -> List[Tuple[str, int]]:
    rows = []
    for label, messages in TRAINING_EXAMPLES.items():
        for message in messages:
            rows.append((message, LABEL2ID[label]))

    random.shuffle(rows)
    return rows


# -----------------------------
# Tokenization / batching
# -----------------------------

def tokenize_batch(
    tokenizer,
    texts: List[str],
    device: torch.device,
):
    encoded = tokenizer(
        texts,
        padding=True,
        truncation=True,
        max_length=MAX_LENGTH,
        return_tensors="pt",
    )
    return {
        "input_ids": encoded["input_ids"].to(device),
        "attention_mask": encoded["attention_mask"].to(device),
    }


# -----------------------------
# Training
# -----------------------------

def train_classifier() -> Tuple[torch.nn.Module, AutoTokenizer]:
    tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME)

    model = AutoModelForSequenceClassification.from_pretrained(
        MODEL_NAME,
        num_labels=len(LABELS),
        id2label=ID2LABEL,
        label2id=LABEL2ID,
    )
    model.to(DEVICE)

    dataset = build_dataset()

    # Hold out one example from each class.
    train_rows = []
    eval_rows = []
    per_class = {i: [] for i in range(len(LABELS))}
    for text, label_id in dataset:
        per_class[label_id].append((text, label_id))

    for label_id, rows in per_class.items():
        eval_rows.append(rows[0])
        train_rows.extend(rows[1:])

    optimizer = torch.optim.AdamW(
        model.parameters(),
        lr=LEARNING_RATE,
        weight_decay=WEIGHT_DECAY,
    )

    total_steps = max(1, (len(train_rows) // BATCH_SIZE + 1) * EPOCHS)
    scheduler = get_linear_schedule_with_warmup(
        optimizer,
        num_warmup_steps=max(1, total_steps // 10),
        num_training_steps=total_steps,
    )

    model.train()

    for epoch in range(EPOCHS):
        random.shuffle(train_rows)
        total_loss = 0.0

        for start in range(0, len(train_rows), BATCH_SIZE):
            batch = train_rows[start:start + BATCH_SIZE]
            texts = [x[0] for x in batch]
            labels = torch.tensor(
                [x[1] for x in batch],
                dtype=torch.long,
                device=DEVICE,
            )

            inputs = tokenize_batch(tokenizer, texts, DEVICE)

            optimizer.zero_grad(set_to_none=True)

            outputs = model(
                input_ids=inputs["input_ids"],
                attention_mask=inputs["attention_mask"],
                labels=labels,
            )

            loss = outputs.loss
            loss.backward()

            torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)

            optimizer.step()
            scheduler.step()

            total_loss += float(loss.detach().cpu())

        print(
            f"Epoch {epoch + 1}/{EPOCHS} "
            f"loss={total_loss / max(1, len(train_rows) // BATCH_SIZE + 1):.4f}"
        )

    # Lightweight validation.
    model.eval()
    correct = 0

    with torch.no_grad():
        for text, expected in eval_rows:
            inputs = tokenize_batch(tokenizer, [text], DEVICE)
            logits = model(**inputs).logits
            predicted = int(logits.argmax(dim=-1).item())
            correct += predicted == expected

    print(
        f"Bootstrap validation accuracy: "
        f"{correct}/{len(eval_rows)} = "
        f"{correct / len(eval_rows):.1%}"
    )

    # Move to CPU before tracing/conversion to keep peak memory predictable.
    model.to("cpu")
    return model.eval(), tokenizer


# -----------------------------
# Core ML conversion
# -----------------------------

class CoreMLWrapper(torch.nn.Module):
    """Returns softmax probabilities and accepts int32 Core ML-friendly token tensors."""

    def __init__(self, hf_model):
        super().__init__()
        self.model = hf_model

    def forward(self, input_ids, attention_mask):
        input_ids = input_ids.to(dtype=torch.long)
        attention_mask = attention_mask.to(dtype=torch.long)

        logits = self.model(
            input_ids=input_ids,
            attention_mask=attention_mask,
        ).logits

        # coremltools does NOT insert a softmax for a ClassifierConfig. It
        # takes the final non-const tensor in the graph and renames it to
        # "<predicted_feature_name>_probs". Without this softmax the
        # classLabel_probs dictionary would hold raw logits, which can be
        # negative and do not sum to 1. Softmaxing here keeps the argmax
        # (and therefore classLabel) unchanged.
        return torch.softmax(logits, dim=-1)


def convert_to_coreml(model, tokenizer) -> ct.models.MLModel:
    wrapper = CoreMLWrapper(model).eval()

    # A fixed example is used for tracing; Core ML receives bounded dynamic
    # RangeDim inputs [1, 256].
    sample_text = (
        "Your bank account ending in 4092 was charged $42.50 at Starbucks."
    )
    sample = tokenizer(
        sample_text,
        return_tensors="pt",
        truncation=True,
        max_length=MAX_LENGTH,
        padding="max_length",
    )

    example_ids = sample["input_ids"].to(dtype=torch.int32)
    example_mask = sample["attention_mask"].to(dtype=torch.int32)

    with torch.no_grad():
        traced = torch.jit.trace(
            wrapper,
            (example_ids, example_mask),
            strict=False,
        )

    dynamic_len = ct.RangeDim(
        lower_bound=MIN_LENGTH,
        upper_bound=MAX_LENGTH,
        default=128,
    )

    inputs = [
        ct.TensorType(
            name="input_ids",
            shape=(1, dynamic_len),
            dtype=np.int32,
        ),
        ct.TensorType(
            name="attention_mask",
            shape=(1, dynamic_len),
            dtype=np.int32,
        ),
    ]

    # Leaving predicted_probabilities_output unset makes coremltools attach the
    # final non-const output (logits) and apply a softmax, which produces the
    # classLabelProbs output alongside classLabel and logits.
    classifier_config = ct.ClassifierConfig(
        LABELS,
        predicted_feature_name="classLabel",
    )

    print("Converting PyTorch -> Core ML ML Program...")

    mlmodel = ct.convert(
        traced,
        source="pytorch",
        inputs=inputs,
        outputs=[
            ct.TensorType(
                # The traced graph now emits softmax probabilities, and the
                # ClassifierConfig renames this output to "classLabel_probs".
                name="classLabel_probs",
                dtype=np.float32,
            )
        ],
        classifier_config=classifier_config,
        convert_to="mlprogram",
        minimum_deployment_target=MIN_IOS_TARGET,
        compute_precision=ct.precision.FLOAT16,
        compute_units=ct.ComputeUnit.ALL,
    )

    # Feature descriptions.
    #
    # An "mlprogram" model keeps its weights in a separate weights file, so it
    # cannot be rebuilt from a spec alone (MLModel(spec) raises unless a
    # weights_dir is also supplied). coremltools exposes settable properties for
    # all of these fields, so edit the live model instead of round-tripping the
    # spec. These persist through save().
    mlmodel.author = "On-Device ML & Apple Silicon Architecture Pipeline"
    mlmodel.version = "1.0.0"
    mlmodel.short_description = (
        "On-device mobile notification category classifier."
    )

    # input_description / output_description are mutable mappings keyed by
    # feature name; assigning to a key sets that feature's shortDescription.
    input_descriptions = {
        "input_ids": "Token IDs produced by the bundled DistilBERT tokenizer.",
        "attention_mask": (
            "Attention mask with 1 for real tokens and 0 for padding."
        ),
    }

    # "logits" is absent because ClassifierConfig consumes it as the source
    # for the softmax probability output. coremltools emits that dictionary as
    # "classLabel_probs".
    output_descriptions = {
        "classLabel": "Predicted notification category.",
        "classLabel_probs": (
            "Probability distribution over notification categories."
        ),
    }

    for name, description in input_descriptions.items():
        if name in mlmodel.input_description:
            mlmodel.input_description[name] = description

    for name, description in output_descriptions.items():
        if name in mlmodel.output_description:
            mlmodel.output_description[name] = description

    return mlmodel


# -----------------------------
# INT4 / INT8 compression
# -----------------------------

def quantize_coreml(mlmodel: ct.models.MLModel) -> ct.models.MLModel:
    print(f"Applying INT{QUANT_BITS} post-training weight compression...")

    if QUANT_BITS == 4:
        quant_dtype = "int4"
        granularity = "per_block"
        block_size = 32
    elif QUANT_BITS == 8:
        quant_dtype = "int8"
        granularity = "per_channel"
        block_size = 32
    else:
        raise ValueError("QUANT_BITS must be 4 or 8.")

    op_config = cto.coreml.OpLinearQuantizerConfig(
        mode="linear_symmetric",
        dtype=quant_dtype,
        granularity=granularity,
        block_size=block_size,
        weight_threshold=512,
    )

    optimization_config = cto.coreml.OptimizationConfig(
        global_config=op_config
    )

    # linear_quantize_weights already returns a fully constructed, loaded
    # MLModel, so it must not be rebuilt from its spec (that fails for
    # "mlprogram" models, whose weights live outside the spec).
    compressed = cto.coreml.linear_quantize_weights(
        mlmodel,
        config=optimization_config,
    )

    return compressed


# -----------------------------
# Deterministic notification summarizer
# -----------------------------

MONEY = r"(?:[$€£₹]\s?\d+(?:[.,]\d{1,2})*|\d+(?:[.,]\d{1,2})*\s?(?:USD|EUR|GBP|INR|₹))"


def summarize_notification(text: str, category: str) -> str:
    """
    Convert a notification into a short action/item line.

    This is intentionally bounded and deterministic:
      - <= 20 words
      - preserves useful transaction/security/action details
      - no generative hallucination
    """

    text = re.sub(r"\s+", " ", text).strip()

    if category == "Finance":
        amount = re.search(MONEY, text, flags=re.I)
        merchant = re.search(
            r"\bat\s+([A-Za-z0-9&.' -]+?)(?:\.|\s+Tap|\s+on\s+|$)",
            text,
            flags=re.I,
        )
        card = re.search(
            r"(?:ending|ends)\s+(?:in\s+)?(\d{4})",
            text,
            flags=re.I,
        )

        if amount and merchant and card:
            amount_s = amount.group(0).replace("  ", " ").strip()
            merchant_s = merchant.group(1).strip(" .")
            last4 = card.group(1)
            return (
                f"{amount_s} charge at {merchant_s} "
                f"on card ending in {last4}."
            )

        if amount:
            return f"Review {amount.group(0)} transaction."

        return "Review the latest bank transaction."

    if category == "Security":
        if re.search(r"verification code|one-time code|otp", text, re.I):
            return "Use the verification code to complete sign-in."
        if re.search(r"new login|sign-in|signed in", text, re.I):
            return "Review the new sign-in and confirm it was you."
        return "Review the security alert."

    if category == "Work":
        return "Review the latest work notification and take the requested action."

    if category == "Social":
        return "Check the new social message or interaction."

    if category == "Promotional":
        return "Review the offer before it expires."

    if category == "Personal":
        return "Check the personal reminder or delivery update."

    return "Review the notification."


# -----------------------------
# Python Core ML verification
# -----------------------------

def coreml_predict(
    mlmodel: ct.models.MLModel,
    tokenizer,
    notification: str,
) -> Tuple[str, str, float]:
    encoded = tokenizer(
        notification,
        truncation=True,
        max_length=MAX_LENGTH,
        padding=True,
        return_tensors="np",
    )

    # The tokenizer can produce a batch dimension of 1.
    input_ids = encoded["input_ids"].astype(np.int32)
    attention_mask = encoded["attention_mask"].astype(np.int32)

    result = mlmodel.predict(
        {
            "input_ids": input_ids,
            "attention_mask": attention_mask,
        }
    )

    category = result["classLabel"]

    # coremltools names the classifier probability dictionary output
    # "classLabel_probs" (underscore), and it replaces the raw "logits"
    # output, which the classifier config consumes as its softmax source.
    probs = result.get("classLabel_probs")
    confidence = float(probs[category]) if probs is not None else float("nan")

    summary = summarize_notification(notification, category)

    return category, summary, confidence


# -----------------------------
# Save tokenizer + labels
# -----------------------------

def save_runtime_assets(tokenizer) -> None:
    assets = Path("NotificationClassifierAssets")
    assets.mkdir(exist_ok=True)

    tokenizer.save_pretrained(assets / "tokenizer")

    with open(assets / "labels.json", "w", encoding="utf-8") as f:
        json.dump(
            {
                "labels": LABELS,
                "max_length": MAX_LENGTH,
                "model_name": MODEL_NAME,
                "quant_bits": QUANT_BITS,
            },
            f,
            indent=2,
        )


# -----------------------------
# Main
# -----------------------------

def main() -> None:
    set_seed()
    print_environment()

    if OUTPUT_DIR.exists():
        print(f"Removing existing {OUTPUT_DIR}...")
        shutil.rmtree(OUTPUT_DIR)

    print("\n[1/5] Fine-tuning compact classifier...")
    model, tokenizer = train_classifier()

    print("\n[2/5] Saving tokenizer/runtime assets...")
    save_runtime_assets(tokenizer)

    print("\n[3/5] Converting to Core ML...")
    fp16_model = convert_to_coreml(model, tokenizer)

    print("\n[4/5] Compressing weights...")
    compressed_model = quantize_coreml(fp16_model)

    print(f"\nSaving {OUTPUT_DIR}...")
    compressed_model.save(str(OUTPUT_DIR))

    print("\n[5/5] Verifying generated .mlpackage...")

    # Reload from disk exactly as an app-side developer would.
    deployed = ct.models.MLModel(
        str(OUTPUT_DIR),
        compute_units=ct.ComputeUnit.ALL,
    )

    sample_notification = (
        "Your bank account ending in 4092 was charged $42.50 at Starbucks. "
        "Tap to view transaction."
    )

    category, summary, confidence = coreml_predict(
        deployed,
        tokenizer,
        sample_notification,
    )

    print("\n=== Verification ===")
    print(f"Input:      {sample_notification}")
    print(f"Category:   {category}")
    print(f"Confidence: {confidence:.4f}")
    print(f"Summary:    {summary}")

    # The bootstrap dataset contains the exact sample. A real production
    # dataset must be evaluated separately before shipping.
    expected_category = "Finance"
    expected_summary = (
        "$42.50 charge at Starbucks on card ending in 4092."
    )

    if category != expected_category:
        raise RuntimeError(
            f"Expected {expected_category}, got {category}. "
            "Retrain with more representative finance examples."
        )

    if summary != expected_summary:
        raise RuntimeError(
            f"Expected summary {expected_summary!r}, got {summary!r}."
        )

    print("\nPASS: generated Core ML model produced the expected test result.")
    print(f"Artifact: {OUTPUT_DIR.resolve()}")
    print(f"Assets:   {Path('NotificationClassifierAssets').resolve()}")


if __name__ == "__main__":
    main()
