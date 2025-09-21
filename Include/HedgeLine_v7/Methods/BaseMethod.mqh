//+------------------------------------------------------------------+
//|                                                  BaseMethod.mqh  |
//|                         Interfaces Base para Métodos de Trading  |
//|                                  Copyright 2025, HedgeLine EA    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, HedgeLine EA"
#property link      "https://www.hedgeline.com"
#property version   "1.00"

// Forward declaration
class CDistanceControl;

//+------------------------------------------------------------------+
//| Estrutura de Sinais de Trading                                  |
//+------------------------------------------------------------------+
struct TradingSignal {
    bool hasSignal;         // Se há sinal válido
    int direction;          // 1=BUY, -1=SELL, 0=NEUTRO
    double entryPrice;      // Preço de entrada sugerido
    double stopLoss;        // Stop Loss sugerido
    double takeProfit;      // Take Profit sugerido
    double confidence;      // Confiança do sinal (0-100%)
    string reason;          // Motivo/descrição do sinal
};

//+------------------------------------------------------------------+
//| Interface para Métodos Principais de Trading                    |
//+------------------------------------------------------------------+
class IMainMethod {
public:
    virtual bool Init(string symbol, ENUM_TIMEFRAMES period, bool debug) = 0;
    virtual TradingSignal GetSignal() = 0;
    virtual string GetMethodName() = 0;
    virtual void OnTick() = 0;
    virtual void OnTrade() = 0;
    virtual void SetDistanceManager(CDistanceControl* distMgr) = 0;  // Para acessar o distance manager
};

//+------------------------------------------------------------------+
//| Interface para Métodos Auxiliares                               |
//+------------------------------------------------------------------+
class IAuxMethod {
public:
    virtual bool Init(string symbol, ENUM_TIMEFRAMES period, bool debug) = 0;
    virtual bool FilterSignal(TradingSignal &signal) = 0;  // Modifica o sinal
    virtual double GetSupportLevel() = 0;
    virtual double GetResistanceLevel() = 0;
    virtual string GetMethodName() = 0;
};

//+------------------------------------------------------------------+