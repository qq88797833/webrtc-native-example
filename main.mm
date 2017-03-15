﻿#include "Header.h"
#include <stdio.h>
#include <stdlib.h>
#include "webrtc/call.h"
#include "webrtc/config.h"
#include "webrtc/logging/rtc_event_log/rtc_event_log.h"
#include "webrtc/media/engine/webrtcvoe.h"
#include "webrtc/modules/audio_coding/codecs/builtin_audio_decoder_factory.h"
#include "webrtc/base/asyncpacketsocket.h"
#include "webrtc/test/frame_generator_capturer.h"
#include "webrtc/logging/rtc_event_log/rtc_event_log.h"
#include "webrtc/modules/audio_mixer/audio_mixer_impl.h"
#include "webrtc/voice_engine/include/voe_external_media.h"

webrtc::Call* g_call = nullptr;
cricket::VoEWrapper* g_voe  = nullptr;
webrtc::AudioSendStream* g_audioSendStream = nullptr;
webrtc::AudioReceiveStream* g_audioReceiveStream = nullptr;
rtc::scoped_refptr<webrtc::AudioDecoderFactory> g_audioDecoderFactory;

int g_audioSendChannelId = -1;
int g_audioReceiveChannelId = -1;
class AudioLoopbackTransport;
AudioLoopbackTransport* g_audioSendTransport = nullptr;

class AudioMixDataCallBack :public webrtc::VoEMediaProcess
{
public:
    virtual void Process(int channel,
                         webrtc::ProcessingTypes type,
                         int16_t audio10ms[],
                         size_t length,
                         int samplingFreq,
                         bool isStereo)
    {
        if (type == webrtc::kPlaybackAllChannelsMixed)
        {
            printf("get remote mix pcm data\n");
        }
        if (type == webrtc::kRecordingAllChannelsMixed)
        {
            printf("get local record pcm data\n");
            //本地声音是连续的，如果做录音mp3应该以本地回调为时间参考，在本地回调时录音
        }
    }
};

class AudioLoopbackTransport:public webrtc::Transport{
public:
    virtual bool SendRtp(const uint8_t* packet,size_t length,const webrtc::PacketOptions& options)
    {
        rtc::PacketTime pTime = rtc::CreatePacketTime(0);
        webrtc::PacketReceiver::DeliveryStatus status = g_call->Receiver()->DeliverPacket(webrtc::MediaType::AUDIO, packet, length, webrtc::PacketTime(pTime.timestamp, pTime.not_before));
        assert(status == webrtc::PacketReceiver::DeliveryStatus::DELIVERY_OK);
        return true;
    }
    virtual bool SendRtcp(const uint8_t* packet, size_t length)
    {
        rtc::PacketTime pTime = rtc::CreatePacketTime(0);
        webrtc::PacketReceiver::DeliveryStatus status = g_call->Receiver()->DeliverPacket(webrtc::MediaType::AUDIO, packet, length, webrtc::PacketTime(pTime.timestamp, pTime.not_before));
        assert(status == webrtc::PacketReceiver::DeliveryStatus::DELIVERY_OK);
        return true;
    }
};


int CreateVoe()
{
    g_audioDecoderFactory = webrtc::CreateBuiltinAudioDecoderFactory();
    g_voe = new cricket::VoEWrapper();
    g_voe->base()->Init(NULL,NULL,g_audioDecoderFactory);
    return 0;
}

int CreateCall()
{
    std::unique_ptr<webrtc::RtcEventLog> event_log = webrtc::RtcEventLog::Create(webrtc::Clock::GetRealTimeClock());
    webrtc::AudioState::Config stateconfig;
    stateconfig.voice_engine = g_voe->engine();
    stateconfig.audio_mixer = webrtc::AudioMixerImpl::Create();
    rtc::scoped_refptr<webrtc::AudioState> audio_state = webrtc::AudioState::Create(stateconfig);
    
    webrtc::Call::Config config(new webrtc::RtcEventLogNullImpl());
    config.audio_state = audio_state;
    config.audio_processing = NULL;
    g_call = webrtc::Call::Create(config);
    
    assert(g_call);
    return 0;
}

int CreateAudioSendStream()
{
    g_audioSendTransport = new AudioLoopbackTransport();
    webrtc::AudioSendStream::Config config(g_audioSendTransport);
    
    g_audioSendChannelId = g_voe->base()->CreateChannel();
    config.voe_channel_id = g_audioSendChannelId;
    g_audioSendStream = g_call->CreateAudioSendStream(config);
    
    assert(g_audioSendStream);
    return 0;
}

int CreateAudioReceiveStream()
{
    webrtc::AudioReceiveStream::Config config;
    config.decoder_factory = g_audioDecoderFactory;
    g_audioReceiveChannelId = g_voe->base()->CreateChannel();
    config.voe_channel_id = g_audioReceiveChannelId;
    
    g_audioReceiveStream = g_call->CreateAudioReceiveStream(config);
    
    assert(g_audioReceiveStream);
    return 0;
}


int StartCall()
{
    g_audioSendStream->Start();
    g_audioReceiveStream->Start();
    return 0;
}

int StartGetMixData()
{
    AudioMixDataCallBack* p = new AudioMixDataCallBack();
    webrtc::VoEExternalMedia* externalMedia = webrtc::VoEExternalMedia::GetInterface(g_voe->engine());
    //回调本地录制数据
    externalMedia->RegisterExternalMediaProcessing(-1, webrtc::kRecordingAllChannelsMixed, *p);
    //回调所有远端的合成数据
    externalMedia->RegisterExternalMediaProcessing(-1, webrtc::kPlaybackAllChannelsMixed, *p);
    return 0;
}

int test_main(NSView* localView, NSView* remoteView)
{
    CreateVoe();
    CreateCall();
    CreateAudioSendStream();
    CreateAudioReceiveStream();
    StartCall();
    StartGetMixData();
    return 0;
}

void stop_test()
{
    g_audioSendStream->Stop();
    g_audioReceiveStream->Stop();
}
