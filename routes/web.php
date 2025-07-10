<?php

use Illuminate\Support\Facades\Route;

Route::get('/', function () {
    return view('welcome');
});


Route::get('/json', function () {
    return response()->json([
        'success' => TRUE,
        'message' => 'Success on load json.'
    ]);
});
