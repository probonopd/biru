/*
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
 * MA 02110-1301, USA.
 *
 */

using Biru.Service.Configs;
using Biru.Service.Serde;
using Biru.Service.Models;

namespace Biru.Service {

    errordomain ErrorAPI {
        UNAVAIL,
        UNKNOWN
    }

    public enum SortType {
        SORT_POPULAR,
        SORT_DATE;

        public string to_string () {
            if (this == SORT_DATE) {
                return "date";
            } else {
                return "popular";
            }
        }
    }

    public class URLBuilder {
        // books and galleries are not exchangable terms
        public static string get_search_url (string query, int page_num, SortType sort) {
            // preprocessing query by replacing all whitespaces with '+'
            string formal_query = query.replace (" ", "+");

            return @"$(Constants.NH_HOME)/api/galleries/search?query=$(formal_query)&page=$(page_num.to_string())&sort=$(sort.to_string())";
        }

        public static string get_homepage_url (int page_num, SortType sort) {
            return @"$(Constants.NH_HOME)/api/galleries/all?page=$(page_num.to_string())&sort=$(sort.to_string())";
        }

        // functions that are called from within objects
        public static string get_book_url (int64 book_id) {
            return @"$(Constants.NH_HOME)/api/gallery/$(book_id.to_string())";
        }

        public static string __get_t_url (string media_id) {
            return @"$(Constants.NH_THUMB)/galleries/$(media_id)";
        }

        public static string __get_i_url (string media_id) {
            return @"$(Constants.NH_IMG)/galleries/$(media_id)";
        }

        public static string get_book_cover_url (string media_id, string ext) {
            return @"$(__get_t_url(media_id))/cover.$(ext)";
        }

        public static string get_book_thumbnail_url (string media_id, string ext) {
            return @"$(__get_t_url(media_id))/thumb.$(ext)";
        }

        public static string get_book_web_url (int64 book_id) {
            return @"$(Constants.NH_HOME)/g/$(book_id.to_string())";
        }

        public static string get_related_books_url (int64 book_id) {
            return @"$(Constants.NH_HOME)/api/gallery/$(book_id.to_string())/related";
        }
    }

    // to create new API instance, create with `new API()`
    public class API {
        private Soup.Session session;
        public string last_query { get; set; default = ""; }
        public int last_page_num { get; set; default = 1; }
        public SortType last_sort { get; set; default = SORT_DATE; }

        // api functions are called asynchronously from the UI, so it returns
        // by emitting signals
        public signal void sig_search_result (List<Book ? > lst);
        public signal void sig_homepage_result (List<Book ? > lst);
        public signal void sig_related_result (List<Book ? > lst);
        public signal void sig_error (Error err);

        // this makes API sharable amongst objects via API.get()
        private static API ? instance;

        // constructor
        public API () {
            this.session = new Soup.Session ();
            this.session.ssl_strict = false;
            this.session.max_conns = 16;
            // this.session.use_thread_context = false;
            this.session.user_agent = Constants.NH_UA;
        }

        public async void search_a (string query, int page_num, SortType sort, Cancellable ? cancl) throws Error {
            this.last_query = query;
            this.last_page_num = page_num;
            this.last_sort = sort;

            var url = URLBuilder.get_search_url (query, page_num, sort);
            var mess = new Soup.Message ("GET", url);
            try {
                InputStream istream = yield session.send_async (mess, cancl);

                var ret = yield Parser.parse_search_result_async (istream);

                sig_search_result (ret);
            } catch (Error e) {
                sig_error (e);
                throw e;
            }
        }

        // synchronous search function
        public List<Book ? > __search (string query, int page_num, SortType sort, Cancellable ? cancl) {
            var url = URLBuilder.get_search_url (query, page_num, sort);
            var mess = new Soup.Message ("GET", url);

            try {
                InputStream istream = this.session.send (mess, cancl);
                var ret = Parser.parse_search_result (istream);
                return ret;
            } catch (Error e) {
                return new List<Book ? >();
            }
        }

        // experimental: bring request to background thread to prevent ui block
        public async void search (string query, int page_num, SortType sort, Cancellable ? cancl) throws Error {
            this.last_query = query;
            this.last_page_num = page_num;
            this.last_sort = sort;

            SourceFunc callb = search.callback;
            var ret = new List<Book ? >();

            new Thread<bool>("request search", () => {
                ret = __search (query, page_num, sort, cancl);
                Idle.add ((owned) callb);
                return true;
            });
            yield;
            sig_search_result (ret);
        }

        public async void homepage_a (int page_num, SortType sort, Cancellable ? cancl) throws Error {
            this.last_page_num = page_num;

            var url = URLBuilder.get_homepage_url (page_num, sort);
            var mess = new Soup.Message ("GET", url);
            try {
                InputStream istream = yield this.session.send_async (mess, cancl);

                var ret = yield Parser.parse_search_result_async (istream);

                sig_homepage_result (ret);
            } catch (Error e) {
                sig_error (e);
                throw e;
            }
        }

        // synchronous function to call in another thread
        public List<Book ? > __homepage (int page_num, SortType sort, Cancellable ? cancl) {
            var url = URLBuilder.get_homepage_url (page_num, sort);
            var mess = new Soup.Message ("GET", url);
            try {
                InputStream istream = this.session.send (mess, cancl);
                var ret = Parser.parse_search_result (istream);
                return ret;
            } catch (Error e) {
                return new List<Book ? >();
            }
        }

        // experimental: bring request to background thread to prevent ui block
        public async void homepage (int page_num, SortType sort, Cancellable ? cancl) throws Error {
            this.last_page_num = page_num;

            var ret = new List<Book ? >();
            SourceFunc callb = homepage.callback;

            new Thread<bool>("request home", () => {
                ret = __homepage (page_num, sort, cancl);
                Idle.add ((owned) callb);
                return true;
            });
            yield;
            sig_homepage_result (ret);
        }

        public async void related (int64 book_id) throws Error {
            var url = URLBuilder.get_related_books_url (book_id);
            var mess = new Soup.Message ("GET", url);

            try {
                InputStream istream = yield this.session.send_async (mess, null);

                var ret = yield Parser.parse_search_result_async (istream);

                sig_related_result (ret);
            } catch (Error e) {
                sig_error (e);
                throw e;
            }
        }

        public static unowned API get () {
            if (instance == null) {
                instance = new API ();
            }
            return instance;
        }

        public static unowned Soup.Session get_session () {
            if (instance == null) {
                instance = new API ();
            }

            return instance.session;
        }
    }
}
