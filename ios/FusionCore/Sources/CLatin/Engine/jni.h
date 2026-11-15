// Array-only adapter for the original LatinIME engine. No JVM or Java runtime.
#pragma once
#include <algorithm>
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>
using jint=int; using jlong=int64_t; using jsize=int; using jfloat=float;
using jboolean=uint8_t; using jobject=void*; using jstring=std::string*;
template<class T> using NativeArray=std::vector<T>;
using jintArray=NativeArray<int>*; using jfloatArray=NativeArray<float>*;
using jbooleanArray=NativeArray<uint8_t>*; using jobjectArray=NativeArray<void*>*;
constexpr jboolean JNI_FALSE=0, JNI_TRUE=1;
struct JNIEnv {
 template<class T> int GetArrayLength(NativeArray<T>* a) { return a ? int(a->size()):0; }
 template<class T> void read(NativeArray<T>*a,int start,int n,T*out) { std::copy_n(a->data()+start,n,out); }
 template<class T> void write(NativeArray<T>*a,int start,int n,const T*in) { std::copy_n(in,n,a->data()+start); }
 void GetIntArrayRegion(jintArray a,int s,int n,int*out){read(a,s,n,out);}
 void GetFloatArrayRegion(jfloatArray a,int s,int n,float*out){read(a,s,n,out);}
 void GetBooleanArrayRegion(jbooleanArray a,int s,int n,uint8_t*out){read(a,s,n,out);}
 void SetIntArrayRegion(jintArray a,int s,int n,const int*in){write(a,s,n,in);}
 void SetFloatArrayRegion(jfloatArray a,int s,int n,const float*in){write(a,s,n,in);}
 void SetBooleanArrayRegion(jbooleanArray a,int s,int n,const uint8_t*in){write(a,s,n,in);}
 void* GetObjectArrayElement(jobjectArray a,int i){return a->at(i);}
 int GetStringLength(jstring s){return int(s->size());}
 int GetStringUTFLength(jstring s){return int(s->size());}
 void GetStringUTFRegion(jstring s,int start,int n,char*out){std::memcpy(out,s->data()+start,n);}
 void DeleteLocalRef(void*){}
};
