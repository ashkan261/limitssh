<?php
/**
 * GitHub: RoyalHaze
 * Date: 9/9/23
 * Time: 6:51 PM
 **/

require __DIR__ . '/App.php';

$app = new App();

$users = $app->syncTraffic();
