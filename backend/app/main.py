
import os
import time
import asyncio
from typing import Optional

import httpx
import numpy as np
import pandas as pd
import websockets
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException, Query, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

load_dotenv()

BINANCE = "https://fapi.binance.com"
BINANCE_WS = "wss://fstream.binance.com/ws"
OPENAI_KEY = os.getenv("OPENAI_API_KEY", "")
OPENAI_MODEL = os.getenv("OPENAI_MODEL", "gpt-5.6-luna")

app = FastAPI(title="Futures AI Radar API", version="1.1.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

class Setup(BaseModel):
    symbol: str
    price: float
    signal: str
    volatility_score: float
    volatility_ratio: float
    atr_pct: float
    rsi: float
    volume_ratio: float
    trend: str
    entry_low: float
    entry_high: float
    stop: float
    tp1: float
    tp2: float
    confidence: float
    reasons: list[str]
    ai_comment: str = ""

class ScannerItem(BaseModel):
    symbol: str
    price: float
    change_24h: float
    volatility_score: float
    atr_pct: float
    volume_ratio: float
    signal: str
    trend: str

class ScannerResponse(BaseModel):
    generated_at: int
    items: list[ScannerItem]

class Candle(BaseModel):
    time: int
    open: float
    high: float
    low: float
    close: float
    volume: float
    closed: bool

def clean_symbol(symbol: str) -> str:
    symbol = symbol.strip().upper()
    if not symbol.isalnum() or len(symbol) < 5 or len(symbol) > 30:
        raise HTTPException(400, "Invalid symbol")
    return symbol

def clean_interval(interval: str) -> str:
    allowed = {"1m","3m","5m","15m","30m","1h","2h","4h","6h","8h","12h","1d"}
    if interval not in allowed:
        raise HTTPException(400, "Unsupported interval")
    return interval

async def get_json(path: str, params: dict):
    async with httpx.AsyncClient(timeout=15) as client:
        r = await client.get(BINANCE + path, params=params)
        r.raise_for_status()
        return r.json()

async def get_klines(symbol: str, interval: str = "5m", limit: int = 250):
    symbol = clean_symbol(symbol)
    interval = clean_interval(interval)
    limit = max(50, min(int(limit), 1000))
    data = await get_json("/fapi/v1/klines", {
        "symbol": symbol, "interval": interval, "limit": limit
    })
    if not data:
        raise HTTPException(404, "No market data")
    df = pd.DataFrame(data, columns=[
        "open_time","open","high","low","close","volume",
        "close_time","quote_volume","trades","taker_base",
        "taker_quote","ignore"
    ])
    for c in ["open","high","low","close","volume"]:
        df[c] = pd.to_numeric(df[c], errors="coerce")
    df["open_time"] = pd.to_numeric(df["open_time"])
    return df

def df_to_candles(df: pd.DataFrame):
    return [
        Candle(
            time=int(r.open_time),
            open=float(r.open),
            high=float(r.high),
            low=float(r.low),
            close=float(r.close),
            volume=float(r.volume),
            closed=True,
        ).model_dump()
        for r in df.itertuples()
    ]

def indicators(df: pd.DataFrame):
    close = df["close"]
    high = df["high"]
    low = df["low"]
    volume = df["volume"]

    tr = pd.concat([
        high-low,
        (high-close.shift(1)).abs(),
        (low-close.shift(1)).abs()
    ], axis=1).max(axis=1)
    atr = tr.ewm(alpha=1/14, adjust=False).mean()

    delta = close.diff()
    gain = delta.clip(lower=0).ewm(alpha=1/14, adjust=False).mean()
    loss = (-delta.clip(upper=0)).ewm(alpha=1/14, adjust=False).mean()
    rs = gain / loss.replace(0, np.nan)
    rsi = 100 - (100/(1+rs))
    rsi = rsi.fillna(50)

    ema20 = close.ewm(span=20, adjust=False).mean()
    ema50 = close.ewm(span=50, adjust=False).mean()

    returns = close.pct_change()
    rv_now = returns.rolling(20).std()
    rv_base = returns.rolling(100).std()
    vol_ratio = rv_now.iloc[-1] / max(rv_base.iloc[-1], 1e-9)
    volume_ratio = volume.iloc[-1] / max(volume.rolling(20).mean().iloc[-1], 1e-9)

    return {
        "price": float(close.iloc[-1]),
        "atr": float(atr.iloc[-1]),
        "atr_pct": float(atr.iloc[-1] / close.iloc[-1] * 100),
        "rsi": float(rsi.iloc[-1]),
        "ema20": float(ema20.iloc[-1]),
        "ema50": float(ema50.iloc[-1]),
        "volatility_ratio": float(vol_ratio),
        "volume_ratio": float(volume_ratio),
        "change_24h": float((close.iloc[-1] / close.iloc[-289] - 1) * 100)
            if len(close) > 289 else float((close.iloc[-1]/close.iloc[0]-1)*100)
    }

def chart_indicators(df: pd.DataFrame):
    close = df["close"]
    high = df["high"]
    low = df["low"]
    volume = df["volume"]

    tr = pd.concat([
        high-low,
        (high-close.shift(1)).abs(),
        (low-close.shift(1)).abs()
    ], axis=1).max(axis=1)
    atr = tr.ewm(alpha=1/14, adjust=False).mean()

    delta = close.diff()
    gain = delta.clip(lower=0).ewm(alpha=1/14, adjust=False).mean()
    loss = (-delta.clip(upper=0)).ewm(alpha=1/14, adjust=False).mean()
    rs = gain / loss.replace(0, np.nan)
    rsi = (100 - (100/(1+rs))).fillna(50)

    ema20 = close.ewm(span=20, adjust=False).mean()
    ema50 = close.ewm(span=50, adjust=False).mean()

    out = []
    for i, r in enumerate(df.itertuples()):
        out.append({
            "time": int(r.open_time),
            "open": float(r.open),
            "high": float(r.high),
            "low": float(r.low),
            "close": float(r.close),
            "volume": float(r.volume),
            "ema20": float(ema20.iloc[i]),
            "ema50": float(ema50.iloc[i]),
            "atr": float(atr.iloc[i]),
            "atrPct": float(atr.iloc[i] / r.close * 100),
            "rsi": float(rsi.iloc[i]),
        })
    return out

def make_setup(symbol: str, d: dict) -> Setup:
    p, atr = d["price"], d["atr"]
    trend = "UP" if d["ema20"] > d["ema50"] else "DOWN"

    score = 50
    score += min(30, max(-20, (d["volatility_ratio"] - 1) * 30))
    score += min(15, max(-15, (d["volume_ratio"] - 1) * 12))
    score = max(0, min(100, score))

    long_ok = trend == "UP" and 48 <= d["rsi"] <= 68
    short_ok = trend == "DOWN" and 32 <= d["rsi"] <= 52

    if score < 62:
        signal = "WAIT"
    elif long_ok:
        signal = "LONG_SETUP"
    elif short_ok:
        signal = "SHORT_SETUP"
    else:
        signal = "WAIT"

    reasons = [
        f"ATR: {d['atr_pct']:.2f}%",
        f"Realized-vol ratio: {d['volatility_ratio']:.2f}x",
        f"Volume ratio: {d['volume_ratio']:.2f}x",
        f"Trend: {trend}",
        f"RSI: {d['rsi']:.1f}",
    ]

    if signal == "LONG_SETUP":
        entry_low, entry_high = p - 0.20*atr, p + 0.10*atr
        stop = entry_low - 1.0*atr
        risk = entry_high - stop
        tp1, tp2 = entry_high + 1.0*risk, entry_high + 2.0*risk
    elif signal == "SHORT_SETUP":
        entry_low, entry_high = p - 0.10*atr, p + 0.20*atr
        stop = entry_high + 1.0*atr
        risk = stop - entry_low
        tp1, tp2 = entry_low - 1.0*risk, entry_low - 2.0*risk
    else:
        entry_low = entry_high = p
        stop = p
        tp1 = p
        tp2 = p

    confidence = max(0, min(95, 45 + 0.35*score + 8*min(d["volume_ratio"], 2)))

    return Setup(
        symbol=symbol.upper(), price=p, signal=signal,
        volatility_score=round(score, 1),
        volatility_ratio=round(d["volatility_ratio"], 3),
        atr_pct=round(d["atr_pct"], 3),
        rsi=round(d["rsi"], 2),
        volume_ratio=round(d["volume_ratio"], 2),
        trend=trend, entry_low=entry_low, entry_high=entry_high,
        stop=stop, tp1=tp1, tp2=tp2,
        confidence=round(confidence, 1),
        reasons=reasons,
    )

async def ai_decision(setup: Setup) -> dict:
    """AI is the decision layer; numeric trade levels stay deterministic."""
    fallback = {
        "signal": setup.signal,
        "confidence": setup.confidence,
        "thesis": "Сценарий сформирован по тренду EMA, RSI, ATR, волатильности и объёму.",
        "invalidation": "Сценарий теряет актуальность при движении против предполагаемого направления и пробое стоп-зоны.",
        "reasons": setup.reasons[:5],
    }
    if not OPENAI_KEY:
        return fallback

    prompt = f"""
Ты — AI-аналитик фьючерсного рынка. Твоя задача — выбрать ОДИН сценарий:
LONG, SHORT или WAIT на основе только переданных числовых данных.

Правила:
- LONG означает, что текущий набор факторов поддерживает сценарий покупки.
- SHORT означает, что факторы поддерживают сценарий продажи.
- WAIT означает отсутствие достаточного подтверждения.
- Не выдумывай цену, новости, стакан или индикаторы, которых нет во входных данных.
- Не давай гарантий и не утверждай, что цена обязательно пойдёт в выбранную сторону.
- confidence — 0..100 и отражает силу совпадения факторов, а не вероятность прибыли.
- Верни только JSON с полями signal, confidence, thesis, invalidation, reasons.

Рынок:
{setup.model_dump_json()}
"""
    headers = {"Authorization": f"Bearer {OPENAI_KEY}", "Content-Type": "application/json"}
    payload = {
        "model": OPENAI_MODEL,
        "input": prompt,
        "max_output_tokens": 500,
    }
    try:
        async with httpx.AsyncClient(timeout=25) as client:
            r = await client.post("https://api.openai.com/v1/responses", headers=headers, json=payload)
            r.raise_for_status()
            raw = r.json().get("output_text", "").strip()
            if raw.startswith("```"):
                raw = raw.strip('`').replace('json\n', '', 1).strip()
            import json
            data = json.loads(raw)
            signal = str(data.get("signal", "WAIT")).upper()
            if signal not in {"LONG", "SHORT", "WAIT"}:
                signal = "WAIT"
            confidence = max(0.0, min(100.0, float(data.get("confidence", 50))))
            return {
                "signal": signal,
                "confidence": confidence,
                "thesis": str(data.get("thesis", ""))[:700],
                "invalidation": str(data.get("invalidation", ""))[:500],
                "reasons": [str(x)[:180] for x in data.get("reasons", [])][:6],
            }
    except Exception:
        return fallback


def apply_ai_signal(setup: Setup, ai: dict) -> Setup:
    """Map AI direction to the existing UI fields while keeping levels ATR-based."""
    signal = ai.get("signal", "WAIT")
    p, atr = setup.price, max(setup.price * 0.0001, (setup.atr_pct / 100) * setup.price)
    if signal == "LONG":
        entry_low, entry_high = p - 0.20*atr, p + 0.10*atr
        stop = entry_low - 1.0*atr
        risk = entry_high - stop
        tp1, tp2 = entry_high + risk, entry_high + 2*risk
    elif signal == "SHORT":
        entry_low, entry_high = p - 0.10*atr, p + 0.20*atr
        stop = entry_high + atr
        risk = stop - entry_low
        tp1, tp2 = entry_low - risk, entry_low - 2*risk
    else:
        entry_low = entry_high = stop = tp1 = tp2 = p

    setup.signal = signal + "_SETUP" if signal != "WAIT" else "WAIT"
    setup.confidence = round(float(ai.get("confidence", setup.confidence)), 1)
    setup.entry_low = entry_low
    setup.entry_high = entry_high
    setup.stop = stop
    setup.tp1 = tp1
    setup.tp2 = tp2
    setup.reasons = list(ai.get("reasons") or setup.reasons)
    setup.ai_comment = (
        f"AI: {signal}. {ai.get('thesis','')} "
        f"Риск/инвалидация: {ai.get('invalidation','')}"
    ).strip()
    return setup

@app.get("/health")
async def health():
    return {"ok": True, "service": "futures-ai-radar"}

@app.get("/setup", response_model=Setup)
async def setup(symbol: str = Query("BTCUSDT"), interval: str = Query("5m")):
    df = await get_klines(symbol, interval, 250)
    s = make_setup(symbol, indicators(df))
    ai = await ai_decision(s)
    return apply_ai_signal(s, ai)

@app.get("/scanner", response_model=ScannerResponse)
async def scanner(
    symbols: str = Query("BTCUSDT,ETHUSDT,SOLUSDT,BNBUSDT,XRPUSDT,DOGEUSDT"),
    interval: str = Query("5m")
):
    result = []
    for symbol in [x.strip().upper() for x in symbols.split(",") if x.strip()]:
        try:
            df = await get_klines(symbol, interval, 250)
            d = indicators(df)
            s = make_setup(symbol, d)
            result.append(ScannerItem(
                symbol=s.symbol, price=s.price, change_24h=d["change_24h"],
                volatility_score=s.volatility_score, atr_pct=s.atr_pct,
                volume_ratio=s.volume_ratio, signal=s.signal, trend=s.trend
            ))
        except Exception:
            continue
    result.sort(key=lambda x: x.volatility_score, reverse=True)
    return ScannerResponse(generated_at=int(time.time()), items=result[:30])

@app.get("/chart")
async def chart(
    symbol: str = Query("BTCUSDT"),
    interval: str = Query("5m"),
    limit: int = Query(240, ge=50, le=1000)
):
    df = await get_klines(symbol, interval, limit)
    return {
        "symbol": clean_symbol(symbol),
        "interval": clean_interval(interval),
        "serverTime": int(time.time() * 1000),
        "candles": chart_indicators(df),
    }

@app.websocket("/ws/market/{symbol}")
async def market_ws(websocket: WebSocket, symbol: str, interval: str = "5m"):
    await websocket.accept()
    symbol = clean_symbol(symbol).lower()
    interval = clean_interval(interval)

    # Binance USD-M Futures market stream. Kline payloads are forwarded
    # in a small normalized shape for the mobile client.
    upstream_url = f"{BINANCE_WS}/{symbol}@kline_{interval}"

    try:
        async with websockets.connect(
            upstream_url,
            ping_interval=20,
            ping_timeout=20,
            close_timeout=5,
            max_size=2**20,
        ) as upstream:
            await websocket.send_json({
                "type": "connected",
                "symbol": symbol.upper(),
                "interval": interval,
            })

            async def client_guard():
                while True:
                    try:
                        await websocket.receive_text()
                    except Exception:
                        return

            guard = asyncio.create_task(client_guard())
            try:
                while not guard.done():
                    try:
                        raw = await asyncio.wait_for(upstream.recv(), timeout=30)
                    except asyncio.TimeoutError:
                        continue

                    import json
                    msg = json.loads(raw)
                    k = msg.get("k")
                    if not k:
                        continue

                    await websocket.send_json({
                        "type": "kline",
                        "time": int(k["t"]),
                        "open": float(k["o"]),
                        "high": float(k["h"]),
                        "low": float(k["l"]),
                        "close": float(k["c"]),
                        "volume": float(k["v"]),
                        "closed": bool(k["x"]),
                        "eventTime": int(msg.get("E", 0)),
                    })
            finally:
                guard.cancel()
                try:
                    await guard
                except asyncio.CancelledError:
                    pass

    except WebSocketDisconnect:
        pass
    except Exception as exc:
        try:
            await websocket.send_json({
                "type": "error",
                "message": f"market stream unavailable: {type(exc).__name__}"
            })
        except Exception:
            pass
    finally:
        try:
            await websocket.close()
        except Exception:
            pass
