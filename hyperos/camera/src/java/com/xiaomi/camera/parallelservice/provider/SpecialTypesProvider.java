package com.xiaomi.camera.parallelservice.provider;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.database.Cursor;
import android.database.MatrixCursor;
import android.net.Uri;
import android.os.Bundle;
import android.os.ParcelFileDescriptor;

/**
 * MiuiCamera 的 SpecialTypesProvider 的最小替身。
 *
 * 背景：HyperOS 4 相册是 Rust 实现（libapp_gallery.so），大图页
 * ExternalPhotoPageActivity 会按 authority
 * com.xiaomi.camera.parallelservice.provider.SpecialTypesProvider 解析 provider；
 * 本移植移除了 MiuiCamera，provider 随之消失，解析失败后直接 unwrap abort。
 * 表现为 Aperture「点开照片 → 系统查看」打不开、AGC 点缩略图闪退。
 *
 * 设计：相册只需要这个 authority 存在，不消费任何行。因此
 *   - query() 返回 0 行游标；
 *   - 若调用方带了 projection，就按 projection 建列，保证按列名查找不会 -1；
 *   - call() 返回 null（MiuiCamera 里该方法是并行服务的控制入口）。
 *
 * 不要在这里加业务逻辑。它不是相机的替代品，只是一个让相册不再拿到 null 的桩。
 */
public class SpecialTypesProvider extends ContentProvider {

    /** 仅在调用方没有传 projection 时使用。列名只是占位，不承载语义。 */
    private static final String[] DEFAULT_COLUMNS = {
            "_id",
            "_data",
            "mime_type",
            "date_modified",
            "width",
            "height",
            "special_type"
    };

    @Override
    public boolean onCreate() {
        return true;
    }

    @Override
    public Cursor query(Uri uri, String[] projection, String selection,
                        String[] selectionArgs, String sortOrder) {
        String[] columns = (projection != null && projection.length > 0)
                ? projection
                : DEFAULT_COLUMNS;
        return new MatrixCursor(columns, 0);
    }

    @Override
    public String getType(Uri uri) {
        return null;
    }

    @Override
    public Uri insert(Uri uri, ContentValues values) {
        return null;
    }

    @Override
    public int delete(Uri uri, String selection, String[] selectionArgs) {
        return 0;
    }

    @Override
    public int update(Uri uri, ContentValues values, String selection,
                      String[] selectionArgs) {
        return 0;
    }

    @Override
    public Bundle call(String method, String arg, Bundle extras) {
        return null;
    }

    @Override
    public ParcelFileDescriptor openFile(Uri uri, String mode) {
        return null;
    }
}
