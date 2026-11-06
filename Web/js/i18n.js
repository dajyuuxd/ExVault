// Internationalization module for Vietnamese and English.
window.EX = window.EX || {};

(function () {
  'use strict';
  const EX = window.EX;

  const vi = {
    'app.title': 'ExVault',
    'app.tagline': 'Kho lưu trữ LAN nội bộ',
    'nav.all_files': 'Tất cả file',
    'nav.tags': 'Nhãn',
    'nav.trash': 'Thùng rác',
    'nav.storage': 'Dung lượng',
    'nav.logout': 'Đăng xuất',
    'nav.login': 'Đăng nhập',
    'top.search_placeholder': 'Tìm kiếm...',
    'top.view_list': 'Danh sách',
    'top.view_grid': 'Lưới',
    'top.theme': 'Giao diện',
    'top.lang': 'Ngôn ngữ',
    'action.upload': 'Tải lên',
    'action.new_folder': 'Thư mục mới',
    'action.download': 'Tải về',
    'action.rename': 'Đổi tên',
    'action.move': 'Di chuyển',
    'action.tag': 'Gắn nhãn',
    'action.delete': 'Xóa',
    'action.restore': 'Khôi phục',
    'action.purge': 'Xóa vĩnh viễn',
    'action.empty_trash': 'Dọn sạch thùng rác',
    'action.cancel': 'Hủy',
    'action.save': 'Lưu',
    'action.close': 'Đóng',
    'action.select_all': 'Chọn tất cả',
    'action.clear_selection': 'Bỏ chọn',
    'action.create': 'Tạo',
    'table.name': 'Tên',
    'table.tags': 'Nhãn',
    'table.size': 'Kích thước',
    'table.date': 'Ngày sửa',
    'dialog.new_folder_title': 'Tạo thư mục mới',
    'dialog.new_folder_prompt': 'Nhập tên thư mục:',
    'dialog.rename_title': 'Đổi tên',
    'dialog.rename_prompt': 'Nhập tên mới:',
    'dialog.confirm_delete_title': 'Xác nhận xóa',
    'dialog.confirm_delete_msg': 'Chuyển {count} mục vào thùng rác?',
    'dialog.confirm_purge_title': 'Xóa vĩnh viễn',
    'dialog.confirm_purge_msg': 'Xóa vĩnh viễn {count} mục? Thao tác này không thể hoàn tác.',
    'dialog.confirm_empty_trash': 'Dọn sạch toàn bộ thùng rác?',
    'dialog.tag_title': 'Quản lý nhãn',
    'dialog.new_tag_name': 'Tên nhãn mới',
    'dialog.new_tag_add': 'Thêm nhãn',
    'dialog.move_title': 'Chọn thư mục đích',
    'login.title': 'Đăng nhập ExVault',
    'login.username': 'Tên đăng nhập',
    'login.password': 'Mật khẩu',
    'login.submit': 'Đăng nhập',
    'login.rate_limited': 'Quá nhiều lần thử thất bại. Vui lòng đợi {seconds} giây.',
    'storage.used_ratio': 'Đã lưu {stored} thay cho {size} ({ratio}%)',
    'storage.free': 'Trống {free}',
    'empty.no_files': 'Thư mục trống',
    'empty.no_trash': 'Thùng rác trống',
    'empty.no_search': 'Không tìm thấy kết quả',
    'status.selected_count': 'Đã chọn {count} mục',
    'status.disconnected': 'Mất kết nối tới ExVault. Đang thử lại...',
    'err.bad_request': 'Yêu cầu không hợp lệ',
    'err.invalid_name': 'Tên mục không hợp lệ',
    'err.unauthorized': 'Phiên đăng nhập đã hết hạn',
    'err.bad_credentials': 'Sai tên đăng nhập hoặc mật khẩu',
    'err.forbidden': 'Không có quyền truy cập',
    'err.not_found': 'Không tìm thấy mục yêu cầu',
    'err.method_not_allowed': 'Phương thức không được hỗ trợ',
    'err.conflict': 'Xung đột dữ liệu',
    'err.name_conflict': 'Tên đã tồn tại trong thư mục này',
    'err.offset_mismatch': 'Lệch khối dữ liệu tải lên',
    'err.not_ready': 'Chưa hoàn tất tải dữ liệu',
    'err.too_large': 'Dung lượng vượt quá giới hạn',
    'err.range_not_satisfiable': 'Dải byte không hợp lệ',
    'err.rate_limited': 'Thao tác quá nhanh. Vui lòng thử lại sau',
    'err.busy': 'Máy chủ đang bận. Vui lòng thử lại',
    'err.insufficient_storage': 'Bộ nhớ máy chủ không đủ dung lượng',
    'err.internal_error': 'Lỗi nội bộ máy chủ',
    'err.unknown': 'Đã xảy ra lỗi không xác định',
    'top.settings': 'Cài đặt',
    'upload.title': 'Tải lên',
    'upload.compressing': 'Đang nén ảnh...',
    'upload.uploading': 'Đang tải lên',
    'upload.processing': 'Đang xử lý...',
    'upload.done': 'Đã hoàn tất',
    'upload.error': 'Lỗi tải lên',
    'upload.canceled': 'Đã hủy',
    'upload.cancel_all': 'Hủy tất cả',
    'upload.clear_done': 'Xóa đã xong',
    'upload.drop_hint': 'Thả file hoặc thư mục vào đây để tải lên',
    'upload.confirm_leave': 'Đang có file được tải lên. Nếu rời đi quá trình tải lên sẽ bị gián đoạn.',
    'upload.folder': 'Tải thư mục lên',
    'settings.title': 'Cài đặt',
    'settings.img_compress': 'Nén ảnh JPEG trước khi tải lên',
    'settings.max_edge': 'Cạnh dài tối đa',
    'settings.quality': 'Chất lượng',
    'settings.keep_orig': 'Giữ nguyên',
    'settings.exif_warning': 'Lưu ý: Quá trình nén sẽ loại bỏ thông tin EXIF.'
  };

  const en = {
    'app.title': 'ExVault',
    'app.tagline': 'Offline LAN Storage',
    'nav.all_files': 'All Files',
    'nav.tags': 'Tags',
    'nav.trash': 'Trash',
    'nav.storage': 'Storage',
    'nav.logout': 'Logout',
    'nav.login': 'Login',
    'top.search_placeholder': 'Search...',
    'top.view_list': 'List',
    'top.view_grid': 'Grid',
    'top.theme': 'Theme',
    'top.lang': 'Language',
    'action.upload': 'Upload',
    'action.new_folder': 'New Folder',
    'action.download': 'Download',
    'action.rename': 'Rename',
    'action.move': 'Move',
    'action.tag': 'Tag',
    'action.delete': 'Delete',
    'action.restore': 'Restore',
    'action.purge': 'Delete Forever',
    'action.empty_trash': 'Empty Trash',
    'action.cancel': 'Cancel',
    'action.save': 'Save',
    'action.close': 'Close',
    'action.select_all': 'Select All',
    'action.clear_selection': 'Clear Selection',
    'action.create': 'Create',
    'table.name': 'Name',
    'table.tags': 'Tags',
    'table.size': 'Size',
    'table.date': 'Date Modified',
    'dialog.new_folder_title': 'Create New Folder',
    'dialog.new_folder_prompt': 'Enter folder name:',
    'dialog.rename_title': 'Rename',
    'dialog.rename_prompt': 'Enter new name:',
    'dialog.confirm_delete_title': 'Confirm Delete',
    'dialog.confirm_delete_msg': 'Move {count} items to trash?',
    'dialog.confirm_purge_title': 'Delete Forever',
    'dialog.confirm_purge_msg': 'Permanently delete {count} items? This cannot be undone.',
    'dialog.confirm_empty_trash': 'Empty all items from trash?',
    'dialog.tag_title': 'Manage Tags',
    'dialog.new_tag_name': 'New tag name',
    'dialog.new_tag_add': 'Add Tag',
    'dialog.move_title': 'Select Destination Folder',
    'login.title': 'Sign In to ExVault',
    'login.username': 'Username',
    'login.password': 'Password',
    'login.submit': 'Sign In',
    'login.rate_limited': 'Too many failed attempts. Please wait {seconds} seconds.',
    'storage.used_ratio': 'Saved {stored} instead of {size} ({ratio}%)',
    'storage.free': '{free} free',
    'empty.no_files': 'Empty folder',
    'empty.no_trash': 'Trash is empty',
    'empty.no_search': 'No results found',
    'status.selected_count': '{count} selected',
    'status.disconnected': 'Disconnected from ExVault. Retrying...',
    'err.bad_request': 'Bad request',
    'err.invalid_name': 'Invalid name',
    'err.unauthorized': 'Unauthorized or session expired',
    'err.bad_credentials': 'Invalid username or password',
    'err.forbidden': 'Access forbidden',
    'err.not_found': 'Item not found',
    'err.method_not_allowed': 'Method not allowed',
    'err.conflict': 'Conflict error',
    'err.name_conflict': 'Name conflict in this folder',
    'err.offset_mismatch': 'Upload offset mismatch',
    'err.not_ready': 'Upload not ready to finish',
    'err.too_large': 'Payload too large',
    'err.range_not_satisfiable': 'Range not satisfiable',
    'err.rate_limited': 'Too many requests. Please wait',
    'err.busy': 'Server busy. Please try again',
    'err.insufficient_storage': 'Insufficient storage on server',
    'err.internal_error': 'Internal server error',
    'err.unknown': 'An unknown error occurred',
    'top.settings': 'Settings',
    'upload.title': 'Uploads',
    'upload.compressing': 'Compressing image...',
    'upload.uploading': 'Uploading',
    'upload.processing': 'Processing...',
    'upload.done': 'Completed',
    'upload.error': 'Upload error',
    'upload.canceled': 'Canceled',
    'upload.cancel_all': 'Cancel all',
    'upload.clear_done': 'Clear completed',
    'upload.drop_hint': 'Drop files or folders here to upload',
    'upload.confirm_leave': 'Uploads are currently in progress. Leaving will interrupt them.',
    'upload.folder': 'Upload folder',
    'settings.title': 'Settings',
    'settings.img_compress': 'Compress JPEG images before upload',
    'settings.max_edge': 'Max dimension',
    'settings.quality': 'Quality',
    'settings.keep_orig': 'Keep original',
    'settings.exif_warning': 'Note: Compression strips EXIF metadata.'
  };

  const tables = { vi, en };

  // Detect user's initial language
  let currentLang = 'vi';
  const saved = typeof localStorage !== 'undefined' ? localStorage.getItem('exv.lang') : null;
  if (saved && (saved === 'vi' || saved === 'en')) {
    currentLang = saved;
  } else if (typeof navigator !== 'undefined' && navigator.language && !navigator.language.toLowerCase().startsWith('vi')) {
    currentLang = 'en';
  }

  EX.lang = currentLang;
  EX.i18nTables = tables;

  EX.setLang = function (code) {
    if (code !== 'vi' && code !== 'en') return;
    EX.lang = code;
    if (typeof localStorage !== 'undefined') {
      localStorage.setItem('exv.lang', code);
    }
    if (typeof EX.render === 'function') {
      EX.render();
    }
  };

  EX.t = function (key, vars = {}) {
    const table = tables[EX.lang] || tables.vi;
    let template = table[key] || tables.en[key] || key;
    if (typeof template === 'string') {
      for (const [k, v] of Object.entries(vars)) {
        template = template.replace(new RegExp(`\\{${k}\\}`, 'g'), String(v));
      }
    }
    return template;
  };

})();
