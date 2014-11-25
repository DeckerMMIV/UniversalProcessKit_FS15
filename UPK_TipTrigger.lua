-- by mor2000

--------------------
-- TipTrigger (that trailers can tip specific fillTypes)


local UPK_TipTrigger_mt = ClassUPK(UPK_TipTrigger,UniversalProcessKit)
InitObjectClass(UPK_TipTrigger, "UPK_TipTrigger")
UniversalProcessKit.addModule("tiptrigger",UPK_TipTrigger)

function UPK_TipTrigger:new(id, parent)
	local self = UniversalProcessKit:new(id, parent, UPK_TipTrigger_mt)
	registerObjectClassName(self, "UPK_TipTrigger")
	
	-- acceptedFillTypes
	
	self.acceptedFillTypes = {}
	
	local acceptedFillTypesArr = getArrayFromUserAttribute(self.nodeId, "acceptedFillTypes")
	for _,fillType in pairs(UniversalProcessKit.fillTypeNameToInt(acceptedFillTypesArr)) do
		self:print('accepting '..tostring(UniversalProcessKit.fillTypeIntToName[fillType])..' ('..tostring(fillType)..')')
		self.acceptedFillTypes[fillType] = true
		self.fillTypesConversionMatrix = self.fillTypesConversionMatrix + FillTypesConversionMatrix:new(fillType)
	end
	
	-- texts

	self.showNotAcceptedWarning = getBoolFromUserAttribute(self.nodeId, "showNotAcceptedWarning", true)
	self.showCapacityReachedWarning = getBoolFromUserAttribute(self.nodeId, "showCapacityReachedWarning", true)

	-- use it in your modDec.xml with these l10n settings if you want to change sth
	--[[
	<l10n>
		<text name="notAcceptedHere"> <en>is not accepted here (test)</en> <de>wird hier nicht angenommen</de> </text>
		<text name="capacityReached"> <en>the maximum filllevel of %s is reached</en> <de>Die maximale Füllmenge von %s ist erreicht</de> </text>
	</l10n>
	--]]
	
	self.allowedVehicles={}
	self.allowedVehicles[UniversalProcessKit.VEHICLE_TIPPER] = getBoolFromUserAttribute(self.nodeId, "allowTipper", true)
	
	self.allowWalker = getBoolFromUserAttribute(self.nodeId, "allowWalker", false)
	
	-- register trigger
	
	self:addTrigger()
	self:registerUpkTipTrigger()

	self:print('loaded TipTrigger successfully')
	
	return self
end

function UPK_TipTrigger:delete()
	self:unregisterUpkTipTrigger()
	self:removeTrigger()
	UPK_TipTrigger:superClass().delete(self)
end

function UPK_TipTrigger:registerUpkTipTrigger()
	table.insert(g_upkTipTrigger,self)
end

function UPK_TipTrigger:unregisterUpkTipTrigger()
	removeValueFromTable(g_upkTipTrigger,self)
end

function UPK_TipTrigger:updateTrailerTipping(trailer, fillDelta, fillType)
	if self.isServer then
		if type(trailer)=="table" and fillDelta~=nil then
			local toomuch=0
			if fillDelta < 0 and fillType~=nil then
				--self:print('fillDelta: '..tostring(fillDelta))
				local fill = self:addFillLevel(-fillDelta,fillType)
				--self:print('fill: '..tostring(fill))
				toomuch = fillDelta + fill -- max 0
			end
			if round(toomuch,8)<0 then
				--self:print('end tipping')
				trailer:onEndTip()
				trailer:setFillLevel(trailer:getFillLevel(fillType)-toomuch, fillType) -- put sth back
			end
		end
	end
end

function UPK_TipTrigger:getTipInfoForTrailer(trailer, tipReferencePointIndex)
	--self:print('UPK_TipTrigger:getTipInfoForTrailer')
	if trailer.upk_currentTipTrigger==self then
		--self:print('trailer.upk_currentTipTrigger==self')
		local minDistance, bestPoint = self:getTipDistanceFromTrailer(trailer, tipReferencePointIndex)
		--self:print('minDistance='..tostring(minDistance)..' bestPoint='..tostring(bestPoint))
		trailerFillType = trailer.currentFillType
		fillType = self:getFillType()
		newFillType = self.fillTypesConversionMatrix[fillType][trailerFillType]
		--self:print('fillType: '..tostring(fillType))
		--self:print('trailerFillType: '..tostring(trailerFillType))
		--self:print('newFillType: '..tostring(newFillType))
		local isAllowed = minDistance<1 and
			self.acceptedFillTypes[newFillType] and
			self:allowFillType(newFillType)
		--self:print('minDistance<1? '..tostring(minDistance<1))
		--self:print('self.acceptedFillTypes[newFillType]? '..tostring(self.acceptedFillTypes[newFillType]))
		--self:print('self:allowFillType(newFillType)? '..tostring(self:allowFillType(newFillType)))
		return isAllowed, minDistance, bestPoint
	end
	return false,math.huge,nil
end

function UPK_TipTrigger:getTipDistanceFromTrailer(trailer, tipReferencePointIndex)
	local minDistance = math.huge
	local returnDistance = math.huge
	local bestPoint=tipReferencePointIndex
	if tipReferencePointIndex ~= nil then
		minDistance=self:getTipDistance(trailer,tipReferencePointIndex)
		if minDistance<math.huge then
			returnDistance=0
		end
	else
		for i,_ in pairs(trailer.tipReferencePoints) do
			if minDistance>1 then
				distance=self:getTipDistance(trailer,i)
				if distance < minDistance then
					bestPoint = i
					minDistance = distance
					returnDistance = 0
				end
			end
		end
	end
	return returnDistance, bestPoint
end

function UPK_TipTrigger:getTipDistance(trailer,tipReferencePointIndex)
	local pointNodeX, pointNodeY, pointNodeZ = getWorldTranslation(trailer.tipReferencePoints[tipReferencePointIndex].node)
	self.raycastTriggerFound = false
	-- looks on top of the reference point if it overlaps with the trigger
	raycastAll(pointNodeX, pointNodeY+20, pointNodeZ, 0, -1, 0, "findMyNodeRaycastCallback", 21, self)
	if self.raycastTriggerFound then
		local triggerX, _, triggerZ = getWorldTranslation(self.nodeId)
		return Utils.vector2Length(pointNodeX-triggerX,pointNodeZ-triggerZ)
	end
	return math.huge
end

function UPK_TipTrigger:findMyNodeRaycastCallback(transformId, x, y, z, distance)
	if transformId==self.nodeId then
		self.raycastTriggerFound = true
		return false
	end
	return true
end

-- show text if the filltype of the trailer is not accepted
function UPK_TipTrigger:getNoAllowedText(trailer)
	-- self:print('UPK_TipTrigger:getNoAllowedText('..tostring(trailer)..')')
	
	local trailerFillType = trailer.currentFillType
	local fillTypeName = self.i18n[UniversalProcessKit.fillTypeIntToName[trailerFillType]]
	local fillType=self:getFillType()
	local newFillType = self.fillTypesConversionMatrix[fillType][trailerFillType]
	
	if newFillType==nil and trailerFillType~=Fillable.FILLTYPE_UNKNOWN and self.showNotAcceptedWarning then
		if string.find(self.i18n["notAcceptedHere"], "%%s")~=nil then
			return string.format(self.i18n["notAcceptedHere"], fillTypeName)
		else
			return fillTypeName..' '..self.i18n["notAcceptedHere"] -- standard: use filltype name in front
		end
	end
	
	if newFillType~=nil and self.showCapacityReachedWarning then
		if string.find(self.i18n["capacityReached"], "%%s")~=nil then
			return string.format(self.i18n["capacityReached"], fillTypeName)
		else
			return self.i18n["capacityReached"] -- use no specific filltype name
		end
	end
	
	return nil
end

function UPK_TipTrigger:triggerUpdate(vehicle,isInTrigger)
	if self.isEnabled and self.isServer then
		if UniversalProcessKit.isVehicleType(vehicle, UniversalProcessKit.VEHICLE_TIPPER) then
			if isInTrigger then
				vehicle.upk_currentTipTrigger=self
				if g_currentMission.trailerTipTriggers[vehicle] == nil then
					g_currentMission.trailerTipTriggers[vehicle] = {}
				end
				table.insert(g_currentMission.trailerTipTriggers[vehicle], self)
			else
				if vehicle.upk_currentTipTrigger==self then
					vehicle.upk_currentTipTrigger=nil
				end
				local triggers = g_currentMission.trailerTipTriggers[vehicle]
				if type(triggers) == "table" then
					removeValueFromTable(triggers,self)
					if #triggers == 0 then
						g_currentMission.trailerTipTriggers[vehicle] = nil
					end
				end
			end
		end
	end
end


