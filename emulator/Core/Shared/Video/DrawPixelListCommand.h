#pragma once
#include "pch.h"
#include "Shared/Video/DrawCommand.h"

struct HudPixelPoint { int32_t X, Y; uint32_t Color; };
class DrawPixelListCommand : public DrawCommand
{
 vector<HudPixelPoint> _points;
protected:
 void InternalDraw() override {
  for(const auto& p:_points) DrawPixel(p.X,p.Y,p.Color);
 }
public:
 DrawPixelListCommand(vector<HudPixelPoint>&& points,int frame) : DrawCommand(frame,1),_points(std::move(points)) {}
};
