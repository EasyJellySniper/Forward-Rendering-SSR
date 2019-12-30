#include "RenderAPI.h"
#include "PlatformBase.h"

// Direct3D 11 implementation of RenderAPI.

#if SUPPORT_D3D11

#include <assert.h>
#include <d3d11.h>
#include "Unity/IUnityGraphicsD3D11.h"
#include <wrl.h>
using namespace Microsoft::WRL;

class RenderAPI_D3D11 : public RenderAPI
{
public:
	RenderAPI_D3D11();
	virtual ~RenderAPI_D3D11() { }

	virtual void ProcessDeviceEvent(UnityGfxDeviceEventType type, IUnityInterfaces* interfaces);
	virtual void CacheForwardGBuffer(void *_color, void *_normal, void *_specular);
	virtual void Release();
	virtual void SetForwardGBuffer();

private:
	ID3D11Device* m_Device;
	ComPtr<ID3D11RenderTargetView> colorRT;
	ComPtr<ID3D11RenderTargetView> normalRT;
	ComPtr<ID3D11RenderTargetView> specularRT;
	ComPtr<ID3D11RenderTargetView> unityRtv;
	ComPtr<ID3D11DepthStencilView> unityDsv;
};


RenderAPI* CreateRenderAPI_D3D11()
{
	return new RenderAPI_D3D11();
}

RenderAPI_D3D11::RenderAPI_D3D11()
{
}

void RenderAPI_D3D11::ProcessDeviceEvent(UnityGfxDeviceEventType type, IUnityInterfaces* interfaces)
{
	switch (type)
	{
	case kUnityGfxDeviceEventInitialize:
	{
		IUnityGraphicsD3D11* d3d = interfaces->Get<IUnityGraphicsD3D11>();
		m_Device = d3d->GetDevice();
		break;
	}
	case kUnityGfxDeviceEventShutdown:
		break;
	}
}

void RenderAPI_D3D11::CacheForwardGBuffer(void *_color, void * _normal, void * _specular)
{
	ID3D11Texture2D *color = (ID3D11Texture2D*)_color;
	ID3D11Texture2D *normal = (ID3D11Texture2D*)_normal;
	ID3D11Texture2D *specular = (ID3D11Texture2D*)_specular;

	D3D11_RENDER_TARGET_VIEW_DESC rtvDesc;
	ZeroMemory(&rtvDesc, sizeof(rtvDesc));
	rtvDesc.Texture2D.MipSlice = 0;
	rtvDesc.ViewDimension = D3D11_RTV_DIMENSION_TEXTURE2D;
	rtvDesc.Format = DXGI_FORMAT_R10G10B10A2_UNORM;	// format for normal rt

	m_Device->CreateRenderTargetView(normal, &rtvDesc, normalRT.GetAddressOf());

	rtvDesc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;	// format for color and specular rt
	m_Device->CreateRenderTargetView(color, &rtvDesc, colorRT.GetAddressOf());
	m_Device->CreateRenderTargetView(specular, &rtvDesc, specularRT.GetAddressOf());
}

void RenderAPI_D3D11::Release()
{
	colorRT.Reset();
	normalRT.Reset();
	specularRT.Reset();
}

void RenderAPI_D3D11::SetForwardGBuffer()
{
	if (colorRT == nullptr || normalRT == nullptr || specularRT == nullptr)
	{
		return;
	}

	ID3D11DeviceContext *ic;
	m_Device->GetImmediateContext(&ic);

	// get unity's render target and depth target
	unityRtv.Reset();
	unityDsv.Reset();
	ic->OMGetRenderTargets(1, unityRtv.GetAddressOf(), unityDsv.GetAddressOf());

	// clear RT
	FLOAT color[4] = { 0,0,0,0 };
	ic->ClearRenderTargetView(colorRT.Get(), color);
	ic->ClearRenderTargetView(specularRT.Get(), color);
	ic->ClearRenderTargetView(normalRT.Get(), color);

	// set unity buffer along with our gbuffers
	ID3D11RenderTargetView *rtv[] = { unityRtv.Get(), colorRT.Get(),specularRT.Get(),normalRT.Get() };
	ic->OMSetRenderTargets(4, rtv, unityDsv.Get());

	ic->Release();
}

#endif // #if SUPPORT_D3D11
