_ = require 'lodash'
moment = require 'moment'
Promise = require 'bluebird'
{Broker} = require('algotrader/rxData').default
import ftWebsocket from 'futu-api'
import { ftCmdID } from 'futu-api'
import {Common, Qot_Common, Trd_Common} from 'futu-api/proto'
{TradeDateMarket, SubType, RehabType, KLType, QotMarket} = Qot_Common
{RetType} = Common
{ModifyOrderOp, OrderType, OrderStatus, SecurityFirm, TrdEnv, TrdMarket, TrdSecMarket, TrdSide, TimeInForce} = Trd_Common

class Futu extends Broker
  @marketMap:
    'hk': QotMarket.QotMarket_HK_Security
    'us': QotMarket.QotMarket_US_Securityx

  @subTypeMap:
    'Basic': SubType.SubType_Basic
    'Broker': SubType.SubType_Broker
    '1': SubType.SubType_KL_1Min
    '5': SubType.SubType_KL_5Min
    '15': SubType.SubType_KL_15Min
    '30': SubType.SubType_KL_30Min
    '1h': SubType.SubType_KL_60Min
    '1d': SubType.SubType_KL_Day
    '1w': SubType.SubType_KL_Week
    '1m': SubType.SubType_KL_Month
    '3m': SubType.SubType_KL_Quarter
    '1y': SubType.SubType_KL_Year

  @freqMap: Futu.subTypeMap

  @klTypeMap:
    '1': KLType.KLType_1Min
    '5': KLType.KLType_5Min
    '15': KLType.KLType_15Min
    '30': KLType.KLType_30Min
    '1h': KLType.KLType_60Min
    '1d': KLType.KLType_Day
    '1w': KLType.KLType_Week
    '1m': KLType.KLType_Month
    '3m': KLType.KLType_Quarter
    '1y': KLType.KLType_Year

  @constant: {
    Common
    KLType
    ModifyOrderOp
    OrderStatus
    OrderType
    Qot_Common
    QotMarket
    RehabType
    RetType
    SecurityFirm
    SubType
    TradeDateMarket
    Trd_Common
    TrdEnv
    TrdMarket
    TrdSide
    TrdSecMarket
  }

  constructor: ({host, port} = {}) ->
    super()
    host ?= 'localhost'
    port ?= 33333
    global.WebSocket = require 'ws'
    return do =>
      await new Promise (resolve, reject) =>
        @ws = new ftWebsocket()
        @ws.start host, port, false, null
        @ws.onlogin = resolve
        @ws.onPush = (cmd, data) =>
          try
            @next
              type: (_.find ftCmdID, cmd: cmd).name
              data: Futu.errHandler data
          catch err
            @error err
      @

  @errHandler: ({errCode, retMsg, retType, s2c}) ->
    if retType != Futu.constant.RetType.RetType_Succeed
      throw new Error "#{errCode}: #{retMsg}"
    else
      s2c

  historyKL: ({market, code, start, end, freq}) ->
    security =
      market: Futu.marketMap[market]
      code: code
    rehabType = RehabType.RehabType_Forward
    klType = Futu.klTypeMap[freq]
    beginTime = (start || moment().subtract freqDuration[freq])
      .format 'YYYY-MM-DD'
    endTime = (end || moment())
      .format 'YYYY-MM-DD HH:mm:ss' 
    {klList} = Futu.errHandler await @ws.RequestHistoryKL c2s: {rehabType, klType, security, beginTime, endTime}
    klList.map (i) ->
      {timestamp, openPrice, highPrice, lowPrice, closePrice, volume, turnover, changeRate} = i
      market: market
      code: code
      freq: freq
      timestamp: timestamp
      open: openPrice
      high: highPrice
      low: lowPrice
      close: closePrice
      volume: volume.low
      turnover: turnover
      changeRate: changeRate
    
  streamKL: ({market, code, freq}) ->
    market ?= 'hk'
    market = Futu.marketMap[market]
    await @ws.Sub
      c2s:
        securityList: [{market, code}]
        subTypeList: [Futu.freqMap[freq]]
        isSubOrUnSub: true
        isRegOrUnRegPush: true

  marketState: ({market, code}) ->
    market ?= 'hk'
    market = Futu.marketMap[market]
    data = Futu.errHandler await @ws.GetMarketState
      c2s:
        securityList: [{market, code}]
    @next 
      type: 'marketState'
      data: data

  basicQuote: ({market, code}) ->
    market ?= 'hk'
    market = Futu.marketMap[market]
    await @ws.Sub
      c2s:
        securityList: [{market, code}]
        subTypeList: [Futu.constant.SubType.SubType_Basic]
        isSubOrUnSub: true
        isRegOrUnRegPush: true

export default Futu
