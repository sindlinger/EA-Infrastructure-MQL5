//+------------------------------------------------------------------+
//|                                              SupDemMethod.mqh    |
//|                    Método Auxiliar Suporte/Resistência           |
//|                                  Copyright 2025, HedgeLine EA    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, HedgeLine EA"
#property link      "https://www.hedgeline.com"
#property version   "1.00"

#include "BaseMethod.mqh"

//+------------------------------------------------------------------+
//| Classe do Método Auxiliar SupDem Volume-Based                   |
//+------------------------------------------------------------------+
class CSupDemVolBased : public IAuxMethod {
private:
    string m_symbol;
    ENUM_TIMEFRAMES m_period;
    bool m_debug;
    double m_lastSupport;
    double m_lastResistance;

    // Parâmetros do método
    int m_lookbackPeriod;
    double m_minStrength;
    double m_minDistance;
    bool m_useFilter;

public:
    //+------------------------------------------------------------------+
    //| Construtor                                                       |
    //+------------------------------------------------------------------+
    CSupDemVolBased() {
        m_lastSupport = 0;
        m_lastResistance = 0;
        m_lookbackPeriod = 50;
        m_minStrength = 2.0;
        m_minDistance = 20;
        m_useFilter = true;
    }

    //+------------------------------------------------------------------+
    //| Configurar parâmetros                                           |
    //+------------------------------------------------------------------+
    void SetParameters(int lookbackPeriod, double minStrength, double minDistance, bool useFilter) {
        m_lookbackPeriod = lookbackPeriod;
        m_minStrength = minStrength;
        m_minDistance = minDistance;
        m_useFilter = useFilter;
    }

    //+------------------------------------------------------------------+
    //| Inicialização                                                   |
    //+------------------------------------------------------------------+
    virtual bool Init(string symbol, ENUM_TIMEFRAMES period, bool debug) {
        m_symbol = symbol;
        m_period = period;
        m_debug = debug;
        m_lastSupport = 0;
        m_lastResistance = 0;

        if(m_debug) {
            Print("🔧 Método Auxiliar SupDem Volume-Based inicializado");
            Print("  Symbol: ", symbol);
            Print("  Period: ", EnumToString(period));
            Print("  Lookback: ", m_lookbackPeriod, " barras");
        }

        return true;
    }

    //+------------------------------------------------------------------+
    //| Filtrar/Modificar Sinal                                         |
    //+------------------------------------------------------------------+
    virtual bool FilterSignal(TradingSignal &signal) {
        if(!m_useFilter) return true;

        // Atualizar níveis de suporte/resistência
        CalculateLevels();

        double currentPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);
        double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);

        // Verificar proximidade aos níveis
        bool nearSupport = false;
        bool nearResistance = false;

        if(m_lastSupport > 0) {
            double distToSupport = MathAbs(currentPrice - m_lastSupport);
            nearSupport = (distToSupport < m_minDistance * point);
        }

        if(m_lastResistance > 0) {
            double distToResistance = MathAbs(currentPrice - m_lastResistance);
            nearResistance = (distToResistance < m_minDistance * point);
        }

        if(m_debug && (nearSupport || nearResistance)) {
            Print("🔧 SupDem: Preço próximo a nível importante");
            if(nearSupport) Print("  Próximo ao Suporte: ", DoubleToString(m_lastSupport, 5));
            if(nearResistance) Print("  Próximo à Resistência: ", DoubleToString(m_lastResistance, 5));
        }

        // Modificar confiança do sinal baseado nos níveis
        if(nearSupport) {
            if(signal.direction <= 0) {  // Sinal de compra ou neutro
                signal.confidence += 20;  // Aumenta confiança
                signal.reason += " [Próximo ao Suporte]";

                // Ajustar SL para abaixo do suporte
                double suggestedSL = m_lastSupport - 10 * point;
                if(signal.stopLoss == 0 || signal.stopLoss < suggestedSL) {
                    signal.stopLoss = suggestedSL;
                    if(m_debug) Print("  SL ajustado para: ", DoubleToString(suggestedSL, 5));
                }
            } else {  // Sinal de venda perto do suporte (contra-indicado)
                signal.confidence -= 15;
                signal.reason += " [⚠️ Venda perto do Suporte]";
            }
        }

        if(nearResistance) {
            if(signal.direction >= 0) {  // Sinal de venda ou neutro
                signal.confidence += 20;  // Aumenta confiança
                signal.reason += " [Próximo à Resistência]";

                // Ajustar SL para acima da resistência
                double suggestedSL = m_lastResistance + 10 * point;
                if(signal.stopLoss == 0 || signal.stopLoss > suggestedSL) {
                    signal.stopLoss = suggestedSL;
                    if(m_debug) Print("  SL ajustado para: ", DoubleToString(suggestedSL, 5));
                }
            } else {  // Sinal de compra perto da resistência (contra-indicado)
                signal.confidence -= 15;
                signal.reason += " [⚠️ Compra perto da Resistência]";
            }
        }

        // Ajustar TP baseado nos níveis
        if(signal.direction > 0 && m_lastResistance > currentPrice) {
            // Para compra, TP pode ser ajustado para antes da resistência
            double suggestedTP = m_lastResistance - 5 * point;
            if(signal.takeProfit == 0 || signal.takeProfit > suggestedTP) {
                signal.takeProfit = suggestedTP;
                if(m_debug) Print("  TP ajustado para resistência: ", DoubleToString(suggestedTP, 5));
            }
        }

        if(signal.direction < 0 && m_lastSupport < currentPrice) {
            // Para venda, TP pode ser ajustado para antes do suporte
            double suggestedTP = m_lastSupport + 5 * point;
            if(signal.takeProfit == 0 || signal.takeProfit < suggestedTP) {
                signal.takeProfit = suggestedTP;
                if(m_debug) Print("  TP ajustado para suporte: ", DoubleToString(suggestedTP, 5));
            }
        }

        // Garantir que confiança fique entre 0 e 100
        signal.confidence = MathMax(0, MathMin(100, signal.confidence));

        if(m_debug) {
            Print("🔧 Sinal filtrado por SupDem");
            Print("  Confiança final: ", signal.confidence, "%");
        }

        return true;
    }

    //+------------------------------------------------------------------+
    //| Obter Nível de Suporte                                          |
    //+------------------------------------------------------------------+
    virtual double GetSupportLevel() {
        return m_lastSupport;
    }

    //+------------------------------------------------------------------+
    //| Obter Nível de Resistência                                      |
    //+------------------------------------------------------------------+
    virtual double GetResistanceLevel() {
        return m_lastResistance;
    }

    //+------------------------------------------------------------------+
    //| Obter Nome do Método                                            |
    //+------------------------------------------------------------------+
    virtual string GetMethodName() {
        return "SupDem Volume-Based";
    }

private:
    //+------------------------------------------------------------------+
    //| Calcular Níveis de Suporte/Resistência                          |
    //+------------------------------------------------------------------+
    void CalculateLevels() {
        // Implementação simplificada - será expandida com indicador real
        double high[], low[], volume[];
        ArraySetAsSeries(high, true);
        ArraySetAsSeries(low, true);
        ArraySetAsSeries(volume, true);

        int copied = CopyHigh(m_symbol, m_period, 0, m_lookbackPeriod, high);
        if(copied <= 0) return;

        CopyLow(m_symbol, m_period, 0, m_lookbackPeriod, low);
        long volumeLong[];
        ArraySetAsSeries(volumeLong, true);
        CopyTickVolume(m_symbol, m_period, 0, m_lookbackPeriod, volumeLong);

        // Converter para double se necessário
        ArrayResize(volume, ArraySize(volumeLong));
        for(int i = 0; i < ArraySize(volumeLong); i++) {
            volume[i] = (double)volumeLong[i];
        }

        // Encontrar máximo e mínimo com maior volume (simplificado)
        double maxVol = 0;
        int maxVolIndex = 0;

        for(int i = 0; i < copied; i++) {
            if(volume[i] > maxVol) {
                maxVol = volume[i];
                maxVolIndex = i;
            }
        }

        // Usar high/low do candle com maior volume como referência inicial
        double baseResistance = high[maxVolIndex];
        double baseSupport = low[maxVolIndex];

        // Refinar com média dos extremos próximos
        double sumHigh = 0, sumLow = 0;
        int countHigh = 0, countLow = 0;
        double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
        double zone = 50 * point;  // Zona de 50 pontos

        for(int i = 0; i < copied; i++) {
            // Coletar highs próximos
            if(MathAbs(high[i] - baseResistance) < zone) {
                sumHigh += high[i];
                countHigh++;
            }
            // Coletar lows próximos
            if(MathAbs(low[i] - baseSupport) < zone) {
                sumLow += low[i];
                countLow++;
            }
        }

        // Calcular médias refinadas
        if(countHigh > 0) {
            m_lastResistance = sumHigh / countHigh;
        } else {
            m_lastResistance = baseResistance;
        }

        if(countLow > 0) {
            m_lastSupport = sumLow / countLow;
        } else {
            m_lastSupport = baseSupport;
        }

        // Validar níveis
        double currentPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);

        // Resistência deve estar acima do preço atual
        if(m_lastResistance <= currentPrice) {
            // Procurar nova resistência acima
            m_lastResistance = 0;
            for(int i = 0; i < copied; i++) {
                if(high[i] > currentPrice && (m_lastResistance == 0 || high[i] < m_lastResistance)) {
                    m_lastResistance = high[i];
                }
            }
        }

        // Suporte deve estar abaixo do preço atual
        if(m_lastSupport >= currentPrice) {
            // Procurar novo suporte abaixo
            m_lastSupport = 0;
            for(int i = 0; i < copied; i++) {
                if(low[i] < currentPrice && low[i] > m_lastSupport) {
                    m_lastSupport = low[i];
                }
            }
        }

        if(m_debug) {
            Print("📊 Níveis S/R calculados:");
            Print("  Resistência: ", DoubleToString(m_lastResistance, 5));
            Print("  Suporte: ", DoubleToString(m_lastSupport, 5));
            Print("  Preço atual: ", DoubleToString(currentPrice, 5));
        }
    }
};

//+------------------------------------------------------------------+