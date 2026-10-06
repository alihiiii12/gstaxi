<?php

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;
use App\Models\RequestModel;
use Illuminate\Contracts\Validation\Validator;
use Illuminate\Http\Exceptions\HttpResponseException;

class StoreRequestRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user() !== null && $this->user()->roll === 'Customer';
    }

    public function rules(): array
    {
        return [
            'carTypeId' => 'required|integer|exists:carTypes,id',
            'type' => 'required|in:'.RequestModel::TYPE_SCHEDULE.','.RequestModel::TYPE_IMMEDIATE,
            'startLocationLongitude' => 'required|numeric|between:-180,180',
            'startLocationLatitude' => 'required|numeric|between:-90,90',
            // خيار A: الطلب الفوري يتطلب تحديد الوجهة قبل الإرسال
            'destLocationLongitude' => 'required|numeric|between:-180,180',
            'destLocationLatitude' => 'required|numeric|between:-90,90',
            'requestDate' => 'required_if:type,'.RequestModel::TYPE_SCHEDULE.'|nullable|date|after:now',
            'locationDesc' => 'nullable|string',
            'startLocationName' => 'nullable|string|max:500',
            'destLocationName' => 'nullable|string|max:500',
            'predectedCost' => 'nullable|numeric|min:0',
            'customerQuotedFare' => 'nullable|numeric|min:0',
            'estimatedDurationMinutes' => 'nullable|numeric|min:0|max:10080',
            'estimatedTripKm' => 'nullable|numeric|min:0|max:2000',
            'discountCode' => 'nullable|string',
            // اختياري: تطبيق الزبون يخدم سوريا بالكامل دون اختيار منطقة
            'serviceAreaId' => 'nullable|integer|exists:service_areas,id',
            // فوري أو حجز مسبق: بث بدون سائق محدد، أو إرسال لسائق محدد اختياريًا
            'targetDriverId' => 'nullable|integer|exists:drivers,id',
            'broadcast' => 'sometimes|boolean',
            'zone_multiplier' => 'nullable|numeric|min:0.1|max:20',
            'zone_multiplier_applied' => 'sometimes|boolean',
        ];
    }

    public function messages(): array
    {
        return [
            'carTypeId.required' => 'نوع السيارة مطلوب',

            'type.required' => 'نوع الطلب مطلوب',
            'type.in' => 'نوع الطلب غير صحيح',

            'startLocationLongitude.required' => 'موقع البداية مطلوب',
            'startLocationLongitude.between' => 'قيمة الموقع غير صحيحة',
            'startLocationLongitude.numeric' => 'قيمة الموقع يجب أن تكون رقم',

            'startLocationLatitude.required' => 'موقع البداية مطلوب',
            'startLocationLatitude.between' => 'قيمة الموقع غير صحيحة',
            'startLocationLatitude.numeric' => 'قيمة الموقع يجب أن تكون رقم',

            'destLocationLongitude.required_if' => 'موقع الوجهة مطلوب',
            'destLocationLongitude.required' => 'موقع الوجهة مطلوب',
            'destLocationLongitude.between' => 'قيمة الموقع غير صحيحة',
            'destLocationLongitude.numeric' => 'قيمة الموقع يجب أن تكون رقم',

            'destLocationLatitude.required_if' => 'موقع الوجهة مطلوب',
            'destLocationLatitude.required' => 'موقع الوجهة مطلوب',
            'destLocationLatitude.between' => 'قيمة الموقع غير صحيحة',
            'destLocationLatitude.numeric' => 'قيمة الموقع يجب أن تكون رقم',

            'requestDate.required_if' => 'تاريخ الحجز المسبق مطلوب',
            'requestDate.after' => 'تاريخ الطلب يجب أن يكون بعد الوقت الحالي',
            'requestDate.date' => 'تاريخ الطلب يجب أن يكون تاريخ',

            'serviceAreaId.exists' => 'معرّف المنطقة غير موجود',
            'targetDriverId.exists' => 'السائق المحدد غير موجود',
        ];
    }

    protected function failedValidation(Validator $validator)
    {
        $errors = implode(' — ', $validator->errors()->all());
        throw new HttpResponseException(response()->json([
            'success' => false,
            'state' => false,
            'message' => $errors !== '' ? $errors : 'فشل التحقق من البيانات',
            'errors' => $errors,
        ], 422));
    }

    protected function failedAuthorization()
    {
        throw new HttpResponseException(response()->json([
            'success' => false,
            'state' => false,
            'message' => 'يجب تسجيل الدخول كزبون لإنشاء طلب',
        ], 403));
    }
}
