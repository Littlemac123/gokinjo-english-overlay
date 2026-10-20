#pragma once
#include "pch.h"
#include "Shared/Video/DrawCommand.h"

// Display-only copies from a captured native frame; source pixels remain live.
struct ScreenRegionCopy
{
 int32_t X, Y;
 uint32_t Width, Height;
 vector<uint32_t> Pixels;
};
class DrawScreenRegionsCommand : public DrawCommand
{
 vector<ScreenRegionCopy> _regions;
protected:
 void InternalDraw() override {
  for(auto& r : _regions) {
   for(uint32_t y = 0; y < r.Height; y++) {
    for(uint32_t x = 0; x < r.Width; x++) { DrawPixel(r.X + x, r.Y + y, r.Pixels[y * r.Width + x]); }
   }
  }
 }
public:
 DrawScreenRegionsCommand(vector<ScreenRegionCopy>&& regions, int startFrame) : DrawCommand(startFrame, 1, false), _regions(std::move(regions)) {}
};
