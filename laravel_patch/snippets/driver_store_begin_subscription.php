<?php
// بعد Driver::create(...) في DriverController::store
DriverSubscriptionService::beginSubscription($driver);
