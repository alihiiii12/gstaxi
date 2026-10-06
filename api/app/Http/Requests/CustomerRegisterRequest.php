<?php

namespace App\Http\Requests;

use Illuminate\Contracts\Validation\Validator;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Http\Exceptions\HttpResponseException;

class CustomerRegisterRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            // بدون unique هنا — لتقادي User Enumeration (VUL-08)؛ التحقق في المتحكم.
            'number' => 'required|string|min:10|max:14',
            'firstName' => 'required_without:fullName|string|max:255',
            'lastName' => 'nullable|string|max:255',
            'fullName' => 'required_without:firstName|string|max:255',
            'password' => 'required|string|min:6|confirmed',
        ];
    }

    public function messages(): array
    {
        return [
            'number.required' => 'رقم الهاتف مطلوب',
            'password.required' => 'كلمة المرور مطلوبة',
            'password.min' => 'كلمة المرور 6 أحرف على الأقل',
            'password.confirmed' => 'تأكيد كلمة المرور غير متطابق',
        ];
    }

    protected function failedValidation(Validator $validator)
    {
        throw new HttpResponseException(response()->json([
            'state' => false,
            'success' => false,
            'message' => $validator->errors()->first() ?? 'فشل التحقق من البيانات',
            'errors' => $validator->errors(),
        ], 422));
    }
}
