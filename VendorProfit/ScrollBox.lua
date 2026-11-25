-- Scroll boxes, all alike (docs/ui-design.md, "Scroll boxes"): a box a
-- little darker than the window, its items and scroll bar inset by PADDING,
-- as tall as its rows up to its most rows, the scroll bar only when there's
-- more than fits, and no box with nothing in it. The To do box set the
-- pattern; every list that scrolls uses this.

local _, ns = ...
local VendorProfit = ns.VendorProfit

local ScrollBox = {}
VendorProfit.ScrollBox = ScrollBox

ScrollBox.PADDING = 6
ScrollBox.BAR_WIDTH = 16
ScrollBox.SHADE = 0.35

-- What a box takes beyond its list: the padding either side and between
-- the list and the bar, and the bar.
ScrollBox.EXTRA_WIDTH = 3 * ScrollBox.PADDING + ScrollBox.BAR_WIDTH
ScrollBox.EXTRA_HEIGHT = 2 * ScrollBox.PADDING

-- The bar's arrows: the box's padding plus the arrow, from each end.
local ARROW = 16

local function ShowBar(scroll, show)
    if scroll.ScrollBar then
        scroll.ScrollBar:SetShown(show)
    end
end

-- A box on parent: the scroll frame, its scroll child (scroll.list) and the
-- shade behind them (scroll.back). Placed with ScrollBox.Place.
function ScrollBox.Create(parent, child)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    local list = child or CreateFrame("Frame", nil, scroll)
    scroll:SetScrollChild(list)
    scroll.list = list
    scroll.back = parent:CreateTexture(nil, "BACKGROUND")
    scroll.back:SetColorTexture(0, 0, 0, ScrollBox.SHADE)
    -- The template shows the bar again whenever the scroll range changes
    -- (unless scrollBarHideable, which hides it at no range); this runs
    -- after it, so the bar shows only when there's something to scroll. In
    -- a short box its arrows nearly met, with no room for the thumb, and a
    -- bar that can't scroll says nothing.
    scroll.scrollBarHideable = true
    scroll:HookScript("OnScrollRangeChanged", function(self, _, yrange)
        ShowBar(self, (yrange or 0) > 0.5)
    end)
    return scroll
end

-- Places a box with its top left at (x, y) from relativeTo's top left, its
-- list listWidth wide, height tall on screen (its most, or less), the list
-- contentHeight in all. With nothing in it (contentHeight 0) there's no
-- box. Returns how tall the box is (0 with none).
function ScrollBox.Place(scroll, relativeTo, x, y, listWidth, height, contentHeight)
    if contentHeight <= 0 then
        ScrollBox.Hide(scroll)
        return 0
    end
    local pad = ScrollBox.PADDING
    local back = scroll.back
    back:ClearAllPoints()
    back:SetPoint("TOPLEFT", relativeTo, "TOPLEFT", x, y)
    back:SetSize(listWidth + ScrollBox.EXTRA_WIDTH, height + ScrollBox.EXTRA_HEIGHT)
    back:Show()
    scroll:ClearAllPoints()
    scroll:SetPoint("TOPLEFT", relativeTo, "TOPLEFT", x + pad, y - pad)
    scroll:SetSize(listWidth, height)
    scroll.list:SetWidth(listWidth)
    scroll.list:SetHeight(contentHeight)
    -- The template puts the bar a little right of the list; here it's held
    -- the same padding from the box's right edge as the items are from its
    -- left, its arrows inside the box.
    local bar = scroll.ScrollBar
    if bar then
        bar:ClearAllPoints()
        bar:SetPoint("TOPRIGHT", back, "TOPRIGHT", -pad, -pad - ARROW)
        bar:SetPoint("BOTTOMRIGHT", back, "BOTTOMRIGHT", -pad, pad + ARROW)
    end
    ShowBar(scroll, contentHeight > height + 0.5)
    -- Shorter than before: not left scrolled past its new end.
    local maxScroll = math.max(contentHeight - height, 0)
    if (scroll:GetVerticalScroll() or 0) > maxScroll then
        scroll:SetVerticalScroll(maxScroll)
    end
    scroll:Show()
    return height + ScrollBox.EXTRA_HEIGHT
end

function ScrollBox.Hide(scroll)
    scroll:Hide()
    scroll.back:Hide()
end
