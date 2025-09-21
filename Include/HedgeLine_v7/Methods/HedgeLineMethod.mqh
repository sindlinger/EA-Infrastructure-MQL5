//+------------------------------------------------------------------+
//|                                            HedgeLineMethod.mqh   |
//|                         Método HedgeLine Original                |
//|                                  Copyright 2025, HedgeLine EA    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, HedgeLine EA"
#property link      "https://www.hedgeline.com"
#property version   "1.00"

#include "BaseMethod.mqh"
#include "../DistanceControl_v7.mqh"

//+------------------------------------------------------------------+
//| Classe do Método HedgeLine                                      |
//+------------------------------------------------------------------+
class CHedgeLineMethod : public IMainMethod {
private:
    string m_symbol;
    ENUM_TIMEFRAMES m_period;
    bool m_debug;
    CDistanceControl* m_distanceMgr;  // Ponteiro para o distance manager

public:
    //+------------------------------------------------------------------+
    //| Inicialização                                                   |
    //+------------------------------------------------------------------+
    virtual bool Init(string symbol, ENUM_TIMEFRAMES period, bool debug) {
        m_symbol = symbol;
        m_period = period;
        m_debug = debug;
        m_distanceMgr = NULL;

        if(m_debug) {
            Print("📊 Método HedgeLine inicializado");
            Print("  Symbol: ", symbol);
            Print("  Period: ", EnumToString(period));
        }
        return true;
    }

    //+------------------------------------------------------------------+
    //| Configurar Distance Manager                                      |
    //+------------------------------------------------------------------+
    virtual void SetDistanceManager(CDistanceControl* distMgr) {
        m_distanceMgr = distMgr;
        if(m_debug) {
            Print("📊 HedgeLine: Distance Manager configurado");
        }
    }

    //+------------------------------------------------------------------+
    //| Obter Sinal de Trading                                          |
    //+------------------------------------------------------------------+
    virtual TradingSignal GetSignal() {
        TradingSignal signal;
        signal.hasSignal = false;
        signal.direction = 0;
        signal.confidence = 0;
        signal.reason = "";
        signal.entryPrice = 0;
        signal.stopLoss = 0;
        signal.takeProfit = 0;

        // Verificar se distance manager está disponível
        if(m_distanceMgr == NULL) {
            signal.reason = "Distance Manager não configurado";
            return signal;
        }

        // Para HedgeLine, sempre permitir sinal
        // A verificação de distância/spread é feita no nível principal

        // HedgeLine usa ordens pendentes em ambas direções
        // Sempre retorna sinal neutro para colocar BuyStop e SellStop
        double distance = m_distanceMgr.CalculateDynamicDistance();

        if(distance > 0) {
            signal.hasSignal = true;
            signal.direction = 0;  // Neutro - coloca ambas ordens pendentes
            signal.confidence = 75.0;  // Confiança padrão do método
            signal.reason = "HedgeLine: Colocar ordens pendentes bidirecionais";

            if(m_debug) {
                Print("✅ Sinal HedgeLine gerado");
                Print("  Distância para ordens: ", DoubleToString(distance, 1), " pontos");
                Print("  Tipo: Ordens pendentes (BuyStop + SellStop)");
            }
        }

        return signal;
    }

    //+------------------------------------------------------------------+
    //| Obter Nome do Método                                            |
    //+------------------------------------------------------------------+
    virtual string GetMethodName() {
        return "HedgeLine";
    }

    //+------------------------------------------------------------------+
    //| Processamento OnTick                                            |
    //+------------------------------------------------------------------+
    virtual void OnTick() {
        // Processamento específico do HedgeLine no OnTick
        // Por enquanto, não há lógica adicional necessária
    }

    //+------------------------------------------------------------------+
    //| Processamento OnTrade                                           |
    //+------------------------------------------------------------------+
    virtual void OnTrade() {
        // Processamento específico do HedgeLine no OnTrade
        // A lógica principal de reversão está no ReversalManager
        if(m_debug) {
            // Pode adicionar debug específico do método aqui
        }
    }
};

//+------------------------------------------------------------------+