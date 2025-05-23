//---------------------------------------------------------------------------------------
//  FILE:    UIStrategyMapItem_Region_LW.uc
//  AUTHOR:  Amineri / Pavonis Interactive
//  PURPOSE: Provides on-map panel for outposts
//			  This provides a scanning button for each outpost, as well as a button for accessing the new Outpost UI
//--------------------------------------------------------------------------------------- 

class UIStrategyMapItem_Region_LW extends UIStrategyMapItem_Region config(LW_UI);

var config bool SHOW_REGION_TOOLTIPS_CTRL;

var localized string m_strOutpostTitle;
var localized string m_strAlertLevel;
var localized string m_strLiberatedRegion;
var localized string m_strStaffingPinText;
var localized string m_strStaffingPinTextMore;
var localized string m_strMonthlyRegionalIncome;

var string CachedRegionLabel;
var string CachedHavenLabel;

simulated function bool CanMakeContact()
{
	return (class'UIUtilities_Strategy'.static.GetXComHQ().IsContactResearched() && (GetRegion().ResistanceLevel == eResLevel_Unlocked));
}

simulated function bool IsContacted()
{
	return ((GetRegion().ResistanceLevel == eResLevel_Contact) || (GetRegion().ResistanceLevel == eResLevel_Outpost));
}

/* Issue # 815 : KDM : When using a controller, UIStrategyMap continuously calls UpdateSelection() --> SelectMapItemNearestLocation().
Now, within SelectMapItemNearestLocation() there is a loop which goes through each XComGameState_GeoscapeEntity and determines if its associated 
strategy map UI item is potentially selectable. The function IsSelectable() within UIStrategyMapItem_Region is rather odd since :
1.] It returns false if IsResHQRegion() is true; in other words, the HQ region isn't selectable.
2.] It returns false if the scan button type isn't eUIScanButtonType_Default, eUIScanButtonType_Contact, or eUIScanButtonType_Tower. 
	Yet, the default scan button type is EUIScanButtonType_MAX which isn't even part of the enumeration.
3.] It doesn't appear to notice a region once it has a relay installed (eResLevel_Outpost).

I have determined that :
1.] Whether a region is the HQ or not should have no bearing on selectability so ignore it entirely.
2.] The scan button type should have no bearing on selectability so ignore it entirely.*/
simulated function bool IsSelectable()
{
	// KDM : The region is selectable if any of these conditions are true :
	// 1.] It is contactable, regardless of whether contacting has commenced.
	// 2.] It has been contacted, regardless of its radio relay status.
	//
	// The region is not selectable if any of these conditions are true : 
	// 1.] It can't be contacted due to insufficient research level. 
	// 2.] It is too far away.
	
	return (CanMakeContact() || IsContacted());
}

simulated function UIStrategyMapItem InitMapItem(out XComGameState_GeoscapeEntity Entity)
{
	local int i;
	local Object TextureObject;
	local Texture2D RegionTexture;
	local Vector2D CenterWorld;
	local X2WorldRegionTemplate RegionTemplate;
	local XComGameState NewGameState;
	local XComGameState_WorldRegion LandingSite;
	local XComGameStateHistory History;
	
	// Spawn the children BEFORE the super.Init because inside that super, it will trigger UpdateFlyoverText and other functions
	// which may assume these children already exist. 

	ContactButton = Spawn(class'UILargeButton', self);
	OutpostButton = Spawn(class'UIButton', self);

	super(UIStrategyMapItem).InitMapItem(Entity);

	ContactButton.InitButton('contactButtonMC', m_strButtonMakeContact, OnContactClicked); // on stage
	ContactButton.OnMouseEventDelegate = ContactButtonOnMouseEvent; 

	OutpostButton.InitButton('towerButtonMC', , OnOutpostClicked); // on stage
	OutpostButton.SetPosition(-5,118);

	ScanButton = Spawn(class'UIScanButton', self).InitScanButton();
	ScanButton.SetPosition(49, 114); //This location is to stop overlapping the pin art.
	ScanButton.SetButtonIcon("");
	ScanButton.SetDefaultDelegate(OnDefaultClicked);  

	History = `XCOMHISTORY;

	LandingSite = XComGameState_WorldRegion(History.GetGameStateForObjectID(Entity.ObjectID));
	RegionTemplate = LandingSite.GetMyTemplate();

	TextureObject = `CONTENT.RequestGameArchetype(RegionTemplate.RegionTexturePath);

	if (TextureObject == none || !TextureObject.IsA('Texture2D'))
	{
		`RedScreen("Could not load region texture" @ RegionTemplate.RegionTexturePath);
		return self;
	}

	RegionTexture = Texture2D(TextureObject);
	RegionMesh = class'Helpers'.static.ConstructRegionActor(RegionTexture);

	for (i = 0; i < NUM_TILES; ++i)
	{
		InitRegionComponent(i, RegionTemplate);
	}

	class'Helpers'.static.GenerateCumulativeTriangleAreaArray(RegionComponents[0], CumulativeTriangleArea);

	// Update the Center location based on the mesh's centroid
	CenterWorld = `EARTH.ConvertWorldToEarth(class'Helpers'.static.GetRegionCenterLocation(RegionComponents[0], true));

	if (Entity.Get2DLocation() != CenterWorld)
	{
		NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("Update Region Center");
		Entity = XComGameState_WorldRegion(NewGameState.CreateStateObject(class'XComGameState_GeoscapeEntity', Entity.ObjectID));
		NewGameState.AddStateObject(Entity);
		Entity.Location.X = CenterWorld.X;
		Entity.Location.Y = CenterWorld.Y;

		`XCOMGAME.GameRuleset.SubmitGameState(NewGameState);
	}

	// KDM : A Long War 2 (contacted) region map item, generally speaking, has 3 buttons; we will say it has :
	// 1.] A radio tower button, which opens up the corresponding haven rebel screen.
	// 2.] A haven information button, which displays the haven region's name, advent strength, vigilance, and force.
	// 3.] A scan button, which starts and stops scanning at the location.
	//
	// Unfortunately, many of these buttons have help icons attached to them within flash when a controller is used.
	// The reason I say "unfortunately", is because they were never designed for Long War 2 usage; sometimes they will 
	// display incorrect icons, while other times they will overlap UI elements they should not. The easiest way to deal 
	// with them, normally, would be to set their visiblity to false, or their alpha to 0; however, they are tweened all
	// over the place within the Actionscript code. The result is that nulling them is the only method which will get rid of them !
	//	
	// Within Actionscript there are 4 help icons :
	// 1.] MapItem_Region --> consoleHint is the help icon which appears to the left of the radio tower button; it must be removed.
	// 2.] StrategyScanButton --> scanHint is the help icon which appears to the right of the scan button, when visible; it must be removed.
	// 3.] StrategyScanButton --> consoleHint appears to the left of the haven information button when no scan button is visible; it must be removed.
	// 4.] StrategyScanButton --> buyHint appears not to be used in region map items so it is left alone.
	if (`ISCONTROLLERACTIVE)
	{
		mc.SetNull("consoleHint");
		ScanButton.mc.SetNull("consoleHint");
		ScanButton.mc.SetNull("scanHint");
	}
	
	return self;
}

function bool ShouldDrawResInfo(XComGameState_WorldRegion RegionState)
{
	if (RegionState.bCanScanForContact || RegionState.HaveMadeContact())
	{
		return true;
	}
	else if( GetStrategyMap() != none && GetStrategyMap().m_eUIState == eSMS_Resistance )
	{
		return true;
	}

	return false;
}

function UpdateFlyoverText()
{
	local XComGameStateHistory History;
	local XComGameState_WorldRegion RegionState;
	local XComGameState_AdventChosen ControllingChosen;
	local String RegionLabel;
	local String HavenLabel;
	local String StateLabel;
	local string HoverInfo;
	local int iResLevel;
	local XComGameState_LWOutpostManager OutpostManager;
	local XComGameState_LWOutpost	OutpostState;

	History = `XCOMHISTORY;
	RegionState = XComGameState_WorldRegion(History.GetGameStateForObjectID(GeoscapeEntityRef.ObjectID));

	OutpostManager = class'XComGameState_LWOutpostManager'.static.GetOutpostManager();
	OutpostState = OutpostManager.GetOutpostForRegion(RegionState);

	HavenLabel = GetHavenLabel(RegionState, OutpostState);
	RegionLabel = GetRegionLabel(RegionState, OutpostState);

	ControllingChosen = RegionState.GetControllingChosen();
	if( ControllingChosen != none && ControllingChosen.bMetXCom && !ControllingChosen.bDefeated && RegionState.HaveMadeContact() )
	{
		AS_SetChosenIcon(ControllingChosen.GetChosenIcon());
	}
	
	HoverInfo = "";
	if (ShowContactButton())
	{
		ContactButton.Show();
		if (ShouldDrawResInfo(RegionState))
		{
			HavenLabel = class'UIResistanceManagement_LW'.default.m_strRebelCountLabel $ ": " $ OutpostState.GetRebelCount();
			HavenLabel = class'UIUtilities_Text'.static.GetColoredText(HavenLabel, GetIncomeColor(RegionState.ResistanceLevel));
		}
	}
	else
	{
		ContactButton.Hide();
	}

	if (RegionState.HaveMadeContact())
		OutpostButton.Show();
	else
		OutpostButton.Hide();

	StateLabel = ""; //Possibly unused. 

	if (IsResHQRegion())
		iResLevel = eResLevel_Outpost + 1;
	else
		iResLevel = RegionState.ResistanceLevel;

	CachedRegionLabel = RegionLabel;
	CachedHavenLabel = HavenLabel;

	SetRegionInfo(RegionLabel, HavenLabel, StateLabel, iResLevel, HoverInfo);
}

function string GetRegionLabel(XComGameState_WorldRegion RegionState, optional XComGameState_LWOutpost OutpostState)
{
	local String RegionLabel, StrAdviser;
	local XGParamTag ParamTag;
	local XComGameState_Unit Liaison;
	local StateObjectReference LiaisonRef;

	if (RegionState.HaveMadeContact())
	{
		ParamTag = XGParamTag(`XEXPANDCONTEXT.FindTag("XGParam"));
		ParamTag.IntValue0 = OutpostState.GetNumRebelsOnJob('Resupply');
		ParamTag.IntValue1 = OutpostState.GetNumRebelsOnJob('Intel');
		ParamTag.IntValue2 = OutpostState.GetNumRebelsOnJob('Recruit');
		RegionLabel = `XEXPAND.ExpandString(m_strStaffingPinText);
		ParamTag.IntValue0 = OutpostState.GetNumRebelsOnJob('Hiding');
		RegionLabel = RegionLabel @ `XEXPAND.ExpandString(m_strStaffingPinTextMore);

		if (OutPostState.HasLiaisonOfKind ('Soldier'))
		{
			LiaisonRef = OutPostState.GetLiaison();
			Liaison = XComGameState_Unit(`XCOMHISTORY.GetGameStateForObjectID(LiaisonRef.ObjectID));
			strAdviser = class'UIUtilities_Text'.static.InjectImage(class'UIUtilities_Image'.static.GetRankIcon(Liaison.GetRank(), Liaison.GetSoldierClassTemplateName()), 16, 16, -2);
		}
		if (OutPostState.HasLiaisonOfKind ('Engineer'))
		{
			strAdviser = class'UIUtilities_Text'.static.InjectImage(class'UIUtilities_Image'.const.EventQueue_Engineer, 16, 16, -2);
		}
		if (OutPostState.HasLiaisonOfKind ('Scientist'))
		{
			strAdviser = class'UIUtilities_Text'.static.InjectImage(class'UIUtilities_Image'.const.EventQueue_Science, 16, 16, -2);
		}
		if (strAdviser != "")
		{
			RegionLabel @= strAdviser;
		}
	}
	else
	{
		RegionLabel = class'UIUtilities_Text'.static.GetColoredText(RegionState.GetMyTemplate().DisplayName, GetRegionLabelColor());
	}
	return RegionLabel;
}

function string GetHavenLabel(XComGameState_WorldRegion RegionState, optional XComGameState_LWOutpost OutpostState)
{
	local String HavenLabel;
	local XGParamTag ParamTag;

	HavenLabel = "";	// Blank string will tell the supply income and region state to hide
	if (RegionState.HaveMadeContact())
	{
		ParamTag = XGParamTag(`XEXPANDCONTEXT.FindTag("XGParam"));

		ParamTag.IntValue0 = int(OutpostState.GetIncomePoolForJob('Resupply'));
		ParamTag.IntValue1 = int(OutpostState.GetProjectedMonthlyIncomeForJob('Resupply'));
		HavenLabel = `XEXPAND.ExpandString(m_strMonthlyRegionalIncome);

		HavenLabel = class'UIUtilities_Text'.static.GetColoredText(HavenLabel, GetIncomeColor(RegionState.ResistanceLevel));
	}

	return HavenLabel;
}

function UpdateFromGeoscapeEntity(const out XComGameState_GeoscapeEntity GeoscapeEntity)
{
	local XComGameState_WorldRegion RegionState;
	local string ScanTitle;
	local string ScanTimeValue;
	local string ScanTimeLabel;
	local string ScanInfo;
	local int DaysRemaining;
	local String RegionLabel;
	local XComGameState_LWOutpostManager OutpostManager;
	local XComGameState_LWOutpost	OutpostState;
	local XGParamTag ParamTag;

	if (!bIsInited) return; 

	super(UIStrategyMapItem).UpdateFromGeoscapeEntity(GeoscapeEntity);

	RegionState = GetRegion();
	if (!RegionState.HaveMadeContact() && !IsAvengerLandedHere() && !RegionState.bCanScanForContact)
	{
		ScanButton.Hide();
	}
	else
	{
		RegionLabel = class'UIUtilities_Text'.static.GetColoredText(RegionState.GetMyTemplate().DisplayName, GetRegionLabelColor());
		OutpostManager = class'XComGameState_LWOutpostManager'.static.GetOutpostManager();
		OutpostState = OutpostManager.GetOutpostForRegion(RegionState);

		if (GetRegionLabel(RegionState, OutpostState) != CachedRegionLabel || GetHavenLabel(RegionState, OutpostState) != CachedHavenLabel)
			UpdateFlyoverText();

		ScanButton.Show();
		if (IsAvengerLandedHere())
		{
			ScanButton.SetButtonState(eUIScanButtonState_Expanded);
			ScanButton.SetButtonType(eUIScanButtonType_Default);
		}
		else
		{
			ScanButton.SetButtonState(eUIScanButtonState_Default);
			ScanButton.SetButtonType(eUIScanButtonType_Default);
		}

		if (RegionState.bCanScanForContact)
		{
			ScanTitle = m_strScanForIntelLabel;
			DaysRemaining = RegionState.GetNumScanDaysRemaining();
			ScanTimeValue = string(DaysRemaining);
			ScanTimeLabel = class'UIUtilities_Text'.static.GetDaysString(DaysRemaining);
			ScanInfo = "";
		}
		else if( RegionState.bCanScanForOutpost )
		{
			ScanTitle = m_strScanForOutpostLabel;
			ScanInfo = GetContactedRegionInfo(RegionState);
			DaysRemaining = RegionState.GetNumScanDaysRemaining();
			ScanTimeValue = string(DaysRemaining);
			ScanTimeLabel = class'UIUtilities_Text'.static.GetDaysString(DaysRemaining);
		}
		else
		{
			ParamTag = XGParamTag(`XEXPANDCONTEXT.FindTag("XGParam"));
			ParamTag.StrValue0 = RegionLabel;
			ScanTitle = `XEXPAND.ExpandString(m_strOutpostTitle);
			ScanInfo = GetContactedRegionInfo(RegionState);
			ScanTimeValue = "";
			ScanTimeLabel = "";
		}
		
		ScanButton.SetText(ScanTitle, ScanInfo, ScanTimeValue, ScanTimeLabel);
		ScanButton.AnimateIcon(`GAME.GetGeoscape().IsScanning() && IsAvengerLandedHere());
		ScanButton.SetScanMeter(RegionState.GetScanPercentComplete());
		ScanButton.Realize();
	}
}

function string GetContactedRegionInfo(XComGameState_WorldRegion RegionState)
{
	local string ScanInfo;
	local XComGameState_WorldRegion_LWStrategyAI RegionalAIState;
	local XGParamTag ParamTag;

	ScanInfo = "";
	RegionalAIState = class'XComGameState_WorldRegion_LWStrategyAI'.static.GetRegionalAI(RegionState);
	if (RegionalAIState != none)
	{
		if (RegionalAIState.bLiberated)
		{
			ScanInfo = m_strLiberatedRegion;
		}
		else if(IsContacted())
		{
			ParamTag = XGParamTag(`XEXPANDCONTEXT.FindTag("XGParam"));
			//Primary text display
			ParamTag.IntValue0 = RegionalAIState.LocalAlertLevel;
			ParamTag.IntValue1 = RegionalAIState.LocalForceLevel;
			ParamTag.IntValue2 = RegionalAIState.LocalVigilanceLevel;
			// Re-did the main m_strAlertLevel to be the mod's previous "short version"
			ScanInfo = `XEXPAND.ExpandString(m_strAlertLevel);
		}
		else
		{
			ScanInfo = "?????";
		}
	}
	return ScanInfo;
}

function OnOutpostClicked(UIButton Button)
{
	local XComGameStateHistory History;
	local XComGameState_WorldRegion RegionState;
	local UIOutpostManagement OutpostScreen;
	local StateObjectReference OutpostRef;
	local XComHQPresentationLayer HQPres;
	local XComGameState_LWOutpostManager OutpostManager;
	local XComGameState_LWOutpost	OutpostState;

	History = `XCOMHISTORY;
	RegionState = XComGameState_WorldRegion(History.GetGameStateForObjectID(GeoscapeEntityRef.ObjectID));

	OutpostManager = class'XComGameState_LWOutpostManager'.static.GetOutpostManager();
	OutpostState = OutpostManager.GetOutpostForRegion(RegionState);

	HQPres = `HQPRES;
	OutpostRef = OutpostState.GetReference();
	OutpostScreen = HQPres.Spawn(class'UIOutpostManagement', HQPres);
	OutpostScreen.SetOutpost(OutpostRef);
	`SCREENSTACK.Push(OutpostScreen);
}

function OnDefaultClicked()
{
	if (GetRegion().ResistanceActive())
	{
		if (!IsAvengerLandedHere())
		{
			if (!DisplayInterruptionPopup())
			{
				GetRegion().ConfirmSelection();
			}
		}
	}
}

// Making a copy of this dialogue chain since the is tied to the XComGameState_Region.CanInteract, which we don't want to override
// On attempted selection, if the Skyranger is considered "busy" (ex. waiting on a POI to complete), display a popup 
// to allow user to choose whether to change activities to the new selection.
function bool DisplayInterruptionPopup()
{
	local XComGameState_GeoscapeEntity EntityState;
	local TDialogueBoxData DialogData;
	local XComGameState NewGameState;
	
	EntityState = GetRegion().GetCurrentEntityInteraction();

	if (EntityState != None && EntityState.ObjectID != GetRegion().ObjectID)
	{
		// display the popup
		GetRegion().BeginInteraction(); // pauses the Geoscape

		//EntityState.OnInterruptionPopup(); -- can't access this, so directly call the TriggerEvent if appropriate
		if (XComGameState_WorldRegion(EntityState) != none)
		{
			NewGameState = class'XComGameStateContext_ChangeContainer'.static.CreateChangeState("Trigger Leaving Contact Site Without Scanning Event");
			`XEVENTMGR.TriggerEvent('LeaveContactWithoutScan', , , NewGameState);
			`XCOMGAME.GameRuleset.SubmitGameState(NewGameState);
		}

		DialogData.strText = class'XComGameState_PointOfInterest'.default.m_strScanInteruptionText; //EntityState.GetInterruptionPopupQueryText();
		DialogData.eType = eDialog_Normal;
		DialogData.strAccept = class'UIDialogueBox'.default.m_strDefaultAcceptLabel;
		DialogData.strCancel = class'UIDialogueBox'.default.m_strDefaultCancelLabel;
		DialogData.fnCallback = InterruptionPopupCallback;
		`HQPRES.UIRaiseDialog( DialogData );

		return true;
	}

	return false;
}

simulated public function InterruptionPopupCallback(Name eAction)
{
	local XComGameState_GeoscapeEntity EntityState;

	if (eAction == 'eUIAction_Accept')
	{
		// Give the entity being interrupted an opportunity to cleanup state
		EntityState = GetRegion().GetCurrentEntityInteraction();
		`assert(EntityState != none);
		//EntityState.HandleInterruption();

		// Attempt to select this entity again, now that the previous interaction has been canceled.
		GetRegion().InteractionComplete(true);
		GetRegion().ConfirmSelection();
	}
	else if(eAction == 'eUIAction_Cancel')
	{
		GetRegion().InteractionComplete(false);
	}
}

function GenerateTooltip(string tooltipHTML)
{
	// KDM : If a controller is being used, and SHOW_REGION_TOOLTIPS_CTRL is false, skip tooltip generation so no region tooltips show up.
	// The problem with region tooltips is that they were never designed for Long War; some of them are quite long, and oftentimes, they provide
	// information which is simply not relevant.
	if ((!`ISCONTROLLERACTIVE) || SHOW_REGION_TOOLTIPS_CTRL)
	{
		super.GenerateTooltip(tooltipHTML);
	}
}

simulated function bool OnUnrealCommand(int cmd, int arg)
{
	local bool bHandled;

	if (!CheckInputIsReleaseOrDirectionRepeat(cmd, arg))
	{
		return true;
	}

	bHandled = true;

	switch(cmd)
	{
		case class'UIUtilities_Input'.const.FXS_BUTTON_A:
			// KDM : A button opens up the "Make Contact" pop up screen if the contact button is visible.
			// Long War 2 code within UpdateFlyoverText() determines if the contact button should be visible.
			if (ContactButton.bIsVisible)
			{
				OnContactClicked(ContactButton);
			}
			// KDM : A button toggles scanning if the Avenger is currently at this region location.
			else if (IsAvengerLandedHere())
			{
				ScanButton.ClickButtonScan();
			}
			// KDM : A button travels to this region location if possible.
			else
			{
				OnDefaultClicked();
			}
			break;

		case class'UIUtilities_Input'.const.FXS_BUTTON_X:
			// KDM : X button opens up this haven's rebel screen if the outpost button is visible.
			// Long War 2 code within UpdateFlyoverText() determines if the outpost button should be visible.
			if (OutpostButton.bIsVisible)
			{
				OnOutpostClicked(OutpostButton);
			}
			break;
			
		default:
			bHandled = false;
			break;		
	}

	return bHandled || super(UIStrategyMapItem).OnUnrealCommand(cmd, arg);
}

defaultproperties
{
	bDisableHitTestWhenZoomedOut = false;

	bProcessesMouseEvents = false;
}

